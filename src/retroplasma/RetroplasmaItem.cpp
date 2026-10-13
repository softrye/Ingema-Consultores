#include "RetroplasmaItem.h"
#include <rhi/qrhi.h>
#include <rhi/qshader.h>
#include <QFile>
#include <QMatrix4x4>
#include <QElapsedTimer>
#include <QQuickWindow>
#include <algorithm>
#include <map>
#include <set>

namespace {
QShader readShader(const QString &path){QFile f(path);return f.open(QIODevice::ReadOnly)?QShader::fromSerialized(f.readAll()):QShader();}
struct GpuTile {
    std::unique_ptr<QRhiBuffer> vertices,indices;
    std::unique_ptr<QRhiTexture> texture;
    std::unique_ptr<QRhiShaderResourceBindings> bindings;
    // Pipeline dies before its bindings/texture: no references to an evicted tile.
    std::unique_ptr<QRhiGraphicsPipeline> pipeline;
    quint32 count=0;
    std::size_t bytes=0;
};
class Renderer final : public QQuickRhiItemRenderer {
    QRhi *m_rhi=nullptr;
    QRhiRenderPassDescriptor *m_pass=nullptr;
    std::unique_ptr<QRhiBuffer> m_uniform;
    std::unique_ptr<QRhiSampler> m_sampler;
    std::map<QString,GpuTile> m_tiles;
    std::set<QString> m_drawKeys;
    std::set<QString> m_failed;
    std::vector<inge::rp::RenderTile> m_selected;
    std::shared_ptr<inge::rp::MetricsMailbox> m_mailbox;
    inge::rp::Mat4 m_camera;
    QShader m_vertex,m_fragment;
    QString m_error;
    bool m_active=false;
    quint64 m_sceneRevision=0;
    bool m_sceneChanged=false;
    void clearGpu(){m_drawKeys.clear();m_tiles.clear();m_failed.clear();m_sampler.reset();m_uniform.reset();m_pass=nullptr;}
    void initialize(QRhiCommandBuffer *)override{
        if(m_rhi!=rhi()){clearGpu();m_rhi=rhi();m_vertex={};m_fragment={};}
        if(m_pass!=renderTarget()->renderPassDescriptor()){clearGpu();m_pass=renderTarget()->renderPassDescriptor();}
    }
    void synchronize(QQuickRhiItem *base)override{
        auto *item=static_cast<RetroplasmaItem *>(base);auto *controller=item->controller();
        m_active=controller&&controller->renderActive();
        if(controller&&m_sceneRevision!=controller->sceneRevision()){
            m_sceneRevision=controller->sceneRevision();m_sceneChanged=true;
        }
        if(controller){m_selected=controller->renderTiles();m_camera=controller->viewProjection();m_mailbox=controller->mailbox();}
        else {m_selected.clear();m_mailbox.reset();}
    }
    void publish(inge::rp::RenderMetrics stats,QElapsedTimer &clock){
        stats.cpuRecordMs=clock.nsecsElapsed()/1e6;stats.error=m_error;
        if(m_rhi){switch(m_rhi->backend()){
            case QRhi::OpenGLES2: stats.backend=QStringLiteral("OpenGL ES / OpenGL");break;
            case QRhi::Vulkan: stats.backend=QStringLiteral("Vulkan");break;
            case QRhi::D3D11: stats.backend=QStringLiteral("D3D11");break;
            case QRhi::D3D12: stats.backend=QStringLiteral("D3D12");break;
            case QRhi::Metal: stats.backend=QStringLiteral("Metal");break;
            default: stats.backend=QStringLiteral("QRhi Null");break;
        }}
        if(m_mailbox){std::lock_guard lock(m_mailbox->mutex);stats.frames=m_mailbox->value.frames+1;m_mailbox->value=stats;}
    }
    bool initializeResources(){
        if(m_uniform&&m_sampler)return true;
        m_uniform.reset(m_rhi->newBuffer(QRhiBuffer::Dynamic,QRhiBuffer::UniformBuffer,80));
        m_sampler.reset(m_rhi->newSampler(QRhiSampler::Linear,QRhiSampler::Linear,QRhiSampler::None,QRhiSampler::ClampToEdge,QRhiSampler::ClampToEdge));
        if(!m_uniform->create()||!m_sampler->create()){m_sampler.reset();m_uniform.reset();m_error=QStringLiteral("RP_UNIFORM_OR_SAMPLER_CREATE_FAILED");return false;}
        return true;
    }
    bool buildPipeline(GpuTile &tile){
        if(!m_vertex.isValid())m_vertex=readShader(QStringLiteral(":/inge/retroplasma/shaders/terrain.vert.qsb"));
        if(!m_fragment.isValid())m_fragment=readShader(QStringLiteral(":/inge/retroplasma/shaders/terrain.frag.qsb"));
        if(!m_vertex.isValid()||!m_fragment.isValid()){m_error=QStringLiteral("RP_SHADER_RESOURCE_INVALID");return false;}
        tile.pipeline.reset(m_rhi->newGraphicsPipeline());
        tile.pipeline->setShaderStages({{QRhiShaderStage::Vertex,m_vertex},{QRhiShaderStage::Fragment,m_fragment}});
        QRhiVertexInputLayout layout;layout.setBindings({{sizeof(inge::rp::Vertex)}});
        layout.setAttributes({{0,0,QRhiVertexInputAttribute::Float3,0},{0,1,QRhiVertexInputAttribute::Float3,12},{0,2,QRhiVertexInputAttribute::Float2,24}});
        tile.pipeline->setVertexInputLayout(layout);tile.pipeline->setShaderResourceBindings(tile.bindings.get());
        tile.pipeline->setTopology(QRhiGraphicsPipeline::Triangles);tile.pipeline->setCullMode(QRhiGraphicsPipeline::Back);
        tile.pipeline->setDepthTest(true);tile.pipeline->setDepthWrite(true);tile.pipeline->setDepthOp(QRhiGraphicsPipeline::LessOrEqual);
        tile.pipeline->setSampleCount(renderTarget()->sampleCount());tile.pipeline->setRenderPassDescriptor(m_pass);
        if(!tile.pipeline->create()){m_error=QStringLiteral("RP_PIPELINE_CREATE_FAILED");return false;}return true;
    }
    void render(QRhiCommandBuffer *cb)override{
        QElapsedTimer clock;clock.start();inge::rp::RenderMetrics stats;
        if(m_sceneChanged){clearGpu();m_error.clear();m_sceneChanged=false;}
        if(!m_active){clearGpu();m_selected.clear();return;}
        if(m_pass!=renderTarget()->renderPassDescriptor()){clearGpu();m_pass=renderTarget()->renderPassDescriptor();}
        if(!initializeResources()){
            cb->beginPass(renderTarget(),QColor(12,23,34),{1.0f,0});cb->endPass();publish(stats,clock);return;
        }
        auto *uploads=m_rhi->nextResourceUpdateBatch();std::set<QString> wanted;std::size_t budget=0;bool replacementReady=true;
        for(const auto &selection:m_selected){
            if(!selection.tile)continue;
            if(budget+selection.tile->bytes>64*1024*1024){m_error=QStringLiteral("RP_GPU_MEMORY_LIMIT");replacementReady=false;continue;}
            wanted.insert(selection.key);budget+=selection.tile->bytes;
        }
        // Preserve the last complete draw until every replacement is GPU-ready.
        for(auto it=m_tiles.begin();it!=m_tiles.end();)if(!wanted.count(it->first)&&!m_drawKeys.count(it->first))it=m_tiles.erase(it);else ++it;
        std::size_t allocated=0;for(const auto &[key,gpu]:m_tiles){Q_UNUSED(key)allocated+=gpu.bytes;}
        for(const auto &selection:m_selected){
            if(!wanted.count(selection.key)||m_tiles.count(selection.key))continue;
            if(m_failed.count(selection.key)){replacementReady=false;continue;}
            const auto &tile=*selection.tile;GpuTile gpu;
            auto reject=[&](){m_failed.insert(selection.key);replacementReady=false;};
            if(allocated+tile.bytes>64*1024*1024){m_error=QStringLiteral("RP_GPU_TRANSITION_MEMORY_LIMIT");reject();continue;}
            if(tile.geometry.vertices.size()>65535){m_error=QStringLiteral("RP_INDEX16_VERTEX_LIMIT");reject();continue;}
            std::vector<quint16> indices;indices.reserve(tile.geometry.indices.size());bool valid=true;
            for(auto index:tile.geometry.indices){if(index>=tile.geometry.vertices.size()){valid=false;break;}indices.push_back(quint16(index));}
            if(!valid||indices.empty()){m_error=QStringLiteral("RP_GPU_INVALID_INDICES");reject();continue;}
            gpu.vertices.reset(m_rhi->newBuffer(QRhiBuffer::Immutable,QRhiBuffer::VertexBuffer,int(tile.geometry.vertices.size()*sizeof(inge::rp::Vertex))));
            gpu.indices.reset(m_rhi->newBuffer(QRhiBuffer::Immutable,QRhiBuffer::IndexBuffer,int(indices.size()*sizeof(quint16))));
            gpu.texture.reset(m_rhi->newTexture(QRhiTexture::RGBA8,tile.texture.size()));
            if(!gpu.vertices->create()||!gpu.indices->create()||!gpu.texture->create()){m_error=QStringLiteral("RP_GPU_ALLOCATION_FAILED");reject();continue;}
            gpu.bindings.reset(m_rhi->newShaderResourceBindings());
            gpu.bindings->setBindings({QRhiShaderResourceBinding::uniformBuffer(0,QRhiShaderResourceBinding::VertexStage|QRhiShaderResourceBinding::FragmentStage,m_uniform.get()),QRhiShaderResourceBinding::sampledTexture(1,QRhiShaderResourceBinding::FragmentStage,gpu.texture.get(),m_sampler.get())});
            if(!gpu.bindings->create()){m_error=QStringLiteral("RP_BINDINGS_CREATE_FAILED");reject();continue;}
            if(!buildPipeline(gpu)){reject();continue;}
            // Update batch copies the payload; local index conversion cannot outlive this call.
            uploads->uploadStaticBuffer(gpu.vertices.get(),tile.geometry.vertices.data());uploads->uploadStaticBuffer(gpu.indices.get(),indices.data());uploads->uploadTexture(gpu.texture.get(),tile.texture);
            gpu.count=quint32(indices.size());gpu.bytes=tile.bytes;allocated+=gpu.bytes;m_tiles.emplace(selection.key,std::move(gpu));
        }
        for(const auto &key:wanted)if(!m_tiles.count(key))replacementReady=false;
        if(replacementReady){
            m_drawKeys=wanted;
            for(auto it=m_tiles.begin();it!=m_tiles.end();)if(!wanted.count(it->first))it=m_tiles.erase(it);else ++it;
        }
        QMatrix4x4 matrix;for(int r=0;r<4;++r)for(int c=0;c<4;++c)matrix(r,c)=float(m_camera.at(r,c));
        matrix=m_rhi->clipSpaceCorrMatrix()*matrix;
        float uniform[20];std::copy(matrix.constData(),matrix.constData()+16,uniform);uniform[16]=0.25f;uniform[17]=1;uniform[18]=0.4f;uniform[19]=0;
        uploads->updateDynamicBuffer(m_uniform.get(),0,80,uniform);
        cb->beginPass(renderTarget(),QColor(12,23,34),{1.0f,0},uploads);
        const auto size=renderTarget()->pixelSize();cb->setViewport({0,0,float(size.width()),float(size.height())});
        for(const auto &[key,gpu]:m_tiles){Q_UNUSED(key)stats.gpuBytes+=gpu.bytes;++stats.textures;}
        for(const auto &key:m_drawKeys){
            auto &gpu=m_tiles.at(key);cb->setGraphicsPipeline(gpu.pipeline.get());cb->setShaderResources(gpu.bindings.get());
            QRhiCommandBuffer::VertexInput binding(gpu.vertices.get(),0);cb->setVertexInput(0,1,&binding,gpu.indices.get(),0,QRhiCommandBuffer::IndexUInt16);cb->drawIndexed(gpu.count);
            stats.triangles+=int(gpu.count/3);++stats.meshes;
        }
        cb->endPass();publish(stats,clock);
    }
public:
    ~Renderer()override{clearGpu();}
};
}
RetroplasmaItem::RetroplasmaItem(QQuickItem *parent):QQuickRhiItem(parent){setAlphaBlending(false);setSampleCount(1);connect(this,&QQuickItem::windowChanged,this,[this](QQuickWindow *){connectPresentation();});}
void RetroplasmaItem::connectPresentation(){
    QObject::disconnect(m_presentConnection);
    if(window()&&m_controller){auto controller=m_controller;m_presentConnection=connect(window(),&QQuickWindow::frameSwapped,this,[controller](){if(controller)controller->framePresented();},Qt::QueuedConnection);}
}
void RetroplasmaItem::setController(RetroplasmaController *controller){if(m_controller==controller)return;QObject::disconnect(m_updateConnection);m_controller=controller;if(controller){m_updateConnection=connect(controller,&RetroplasmaController::renderChanged,this,[this](){update();});controller->setViewport(width(),height());}connectPresentation();emit controllerChanged();update();}
QQuickRhiItemRenderer *RetroplasmaItem::createRenderer(){return new Renderer;}
void RetroplasmaItem::geometryChange(const QRectF &now,const QRectF &before){QQuickRhiItem::geometryChange(now,before);if(m_controller)m_controller->setViewport(now.width(),now.height());}

#include "RetroplasmaItem.h"
#include <rhi/qrhi.h>
#include <rhi/qshader.h>
#include <QFile>
#include <QMatrix4x4>
#include <QElapsedTimer>
#include <map>
#include <set>

namespace {
QShader readShader(const QString &path){QFile f(path);return f.open(QIODevice::ReadOnly)?QShader::fromSerialized(f.readAll()):QShader();}
struct GpuTile {
    std::unique_ptr<QRhiBuffer> vertices,indices;
    std::unique_ptr<QRhiTexture> texture;
    std::unique_ptr<QRhiShaderResourceBindings> bindings;
    quint32 count=0;
    std::size_t bytes=0;
};
class Renderer final : public QQuickRhiItemRenderer {
    QRhi *m_rhi=nullptr;
    QRhiRenderPassDescriptor *m_pass=nullptr;
    std::unique_ptr<QRhiBuffer> m_uniform;
    std::unique_ptr<QRhiSampler> m_sampler;
    std::unique_ptr<QRhiShaderResourceBindings> m_layout;
    std::unique_ptr<QRhiGraphicsPipeline> m_pipeline;
    std::map<QString,GpuTile> m_tiles;
    std::vector<inge::rp::RenderTile> m_selected;
    std::shared_ptr<inge::rp::MetricsMailbox> m_mailbox;
    inge::rp::Mat4 m_camera;
    QString m_error;
    bool m_active=false;
    bool m_rebuild=true;
    void clearGpu(){m_tiles.clear();m_pipeline.reset();m_layout.reset();m_sampler.reset();m_uniform.reset();m_pass=nullptr;}
    void initialize(QRhiCommandBuffer *)override{
        if(m_rhi!=rhi()){clearGpu();m_rhi=rhi();m_rebuild=true;}
        if(m_pass!=renderTarget()->renderPassDescriptor()){m_pipeline.reset();m_pass=renderTarget()->renderPassDescriptor();m_rebuild=true;}
    }
    void synchronize(QQuickRhiItem *base)override{
        auto *item=static_cast<RetroplasmaItem *>(base);auto *controller=item->controller();
        m_active=controller&&controller->active();
        if(controller){m_selected=controller->renderTiles();m_camera=controller->viewProjection();m_mailbox=controller->mailbox();}
        else {m_selected.clear();m_mailbox.reset();}
    }
    bool buildPipeline(){
        if(m_uniform==nullptr){
            m_uniform.reset(m_rhi->newBuffer(QRhiBuffer::Dynamic,QRhiBuffer::UniformBuffer,80));
            if(!m_uniform->create())return false;
            m_sampler.reset(m_rhi->newSampler(QRhiSampler::Linear,QRhiSampler::Linear,QRhiSampler::None,QRhiSampler::ClampToEdge,QRhiSampler::ClampToEdge));
            if(!m_sampler->create())return false;
        }
        // A real tile supplies layout-compatible bindings; there is no dummy texture.
        if(m_tiles.empty())return true;
        const auto vertex=readShader(QStringLiteral(":/inge/retroplasma/shaders/terrain.vert.qsb"));
        const auto fragment=readShader(QStringLiteral(":/inge/retroplasma/shaders/terrain.frag.qsb"));
        if(!vertex.isValid()||!fragment.isValid()){m_error=QStringLiteral("RP_SHADER_RESOURCE_INVALID");return false;}
        m_pipeline.reset(m_rhi->newGraphicsPipeline());
        m_pipeline->setShaderStages({{QRhiShaderStage::Vertex,vertex},{QRhiShaderStage::Fragment,fragment}});
        QRhiVertexInputLayout layout;layout.setBindings({{sizeof(inge::rp::Vertex)}});
        layout.setAttributes({{0,0,QRhiVertexInputAttribute::Float3,0},{0,1,QRhiVertexInputAttribute::Float3,12},{0,2,QRhiVertexInputAttribute::Float2,24}});
        m_pipeline->setVertexInputLayout(layout);
        m_pipeline->setShaderResourceBindings(m_tiles.begin()->second.bindings.get());
        m_pipeline->setTopology(QRhiGraphicsPipeline::Triangles);
        m_pipeline->setCullMode(QRhiGraphicsPipeline::Back);
        m_pipeline->setDepthTest(true);m_pipeline->setDepthWrite(true);
        m_pipeline->setDepthOp(QRhiGraphicsPipeline::LessOrEqual);
        m_pipeline->setSampleCount(renderTarget()->sampleCount());
        m_pipeline->setRenderPassDescriptor(m_pass);
        if(!m_pipeline->create()){m_error=QStringLiteral("RP_PIPELINE_CREATE_FAILED");m_pipeline.reset();return false;}
        m_rebuild=false;return true;
    }
    void render(QRhiCommandBuffer *cb)override{
        QElapsedTimer clock;clock.start();inge::rp::RenderMetrics stats;
        if(!m_active){clearGpu();m_selected.clear();return;}
        if(!m_uniform&&!buildPipeline()){m_error=QStringLiteral("RP_UNIFORM_OR_SAMPLER_CREATE_FAILED");return;}
        auto *uploads=m_rhi->nextResourceUpdateBatch();
        std::set<QString> wanted;std::size_t budget=0;
        for(const auto &selection:m_selected){
            if(!selection.tile||budget+selection.tile->bytes>64*1024*1024)continue;
            wanted.insert(selection.key);budget+=selection.tile->bytes;
        }
        for(auto it=m_tiles.begin();it!=m_tiles.end();)if(!wanted.count(it->first))it=m_tiles.erase(it);else ++it;
        for(const auto &selection:m_selected){
            if(!wanted.count(selection.key)||m_tiles.count(selection.key))continue;
            const auto &tile=*selection.tile;GpuTile gpu;
            gpu.vertices.reset(m_rhi->newBuffer(QRhiBuffer::Immutable,QRhiBuffer::VertexBuffer,int(tile.geometry.vertices.size()*sizeof(inge::rp::Vertex))));
            gpu.indices.reset(m_rhi->newBuffer(QRhiBuffer::Immutable,QRhiBuffer::IndexBuffer,int(tile.geometry.indices.size()*sizeof(std::uint32_t))));
            gpu.texture.reset(m_rhi->newTexture(QRhiTexture::RGBA8,tile.texture.size()));
            if(!gpu.vertices->create()||!gpu.indices->create()||!gpu.texture->create()){m_error=QStringLiteral("RP_GPU_ALLOCATION_FAILED");continue;}
            gpu.bindings.reset(m_rhi->newShaderResourceBindings());
            gpu.bindings->setBindings({QRhiShaderResourceBinding::uniformBuffer(0,QRhiShaderResourceBinding::VertexStage|QRhiShaderResourceBinding::FragmentStage,m_uniform.get()),QRhiShaderResourceBinding::sampledTexture(1,QRhiShaderResourceBinding::FragmentStage,gpu.texture.get(),m_sampler.get())});
            if(!gpu.bindings->create()){m_error=QStringLiteral("RP_BINDINGS_CREATE_FAILED");continue;}
            uploads->uploadStaticBuffer(gpu.vertices.get(),tile.geometry.vertices.data());
            uploads->uploadStaticBuffer(gpu.indices.get(),tile.geometry.indices.data());
            uploads->uploadTexture(gpu.texture.get(),tile.texture);
            gpu.count=quint32(tile.geometry.indices.size());gpu.bytes=tile.bytes;
            m_tiles.emplace(selection.key,std::move(gpu));m_rebuild=true;
        }
        if(m_rebuild&&!m_tiles.empty())buildPipeline();
        QMatrix4x4 matrix;for(int r=0;r<4;++r)for(int c=0;c<4;++c)matrix(r,c)=float(m_camera.at(r,c));
        matrix=m_rhi->clipSpaceCorrMatrix()*matrix;
        float uniform[20];std::copy(matrix.constData(),matrix.constData()+16,uniform);uniform[16]=0.25f;uniform[17]=1;uniform[18]=0.4f;uniform[19]=0;
        uploads->updateDynamicBuffer(m_uniform.get(),0,80,uniform);
        cb->beginPass(renderTarget(),QColor(12,23,34),{1.0f,0},uploads);
        if(m_pipeline){
            cb->setGraphicsPipeline(m_pipeline.get());const auto size=renderTarget()->pixelSize();cb->setViewport({0,0,float(size.width()),float(size.height())});
            for(auto &[key,gpu]:m_tiles){Q_UNUSED(key)cb->setShaderResources(gpu.bindings.get());QRhiCommandBuffer::VertexInput binding(gpu.vertices.get(),0);cb->setVertexInput(0,1,&binding,gpu.indices.get(),0,QRhiCommandBuffer::IndexUInt32);cb->drawIndexed(gpu.count);stats.triangles+=int(gpu.count/3);stats.gpuBytes+=gpu.bytes;++stats.meshes;++stats.textures;}
        }
        cb->endPass();
        stats.cpuRecordMs=clock.nsecsElapsed()/1e6;stats.error=m_error;
        stats.backend=QString::number(int(m_rhi->backend()));
        if(m_mailbox){std::lock_guard lock(m_mailbox->mutex);stats.frames=m_mailbox->value.frames+1;m_mailbox->value=stats;}
    }
public:
    ~Renderer()override{clearGpu();}
};
}
RetroplasmaItem::RetroplasmaItem(QQuickItem *parent):QQuickRhiItem(parent){setAlphaBlending(false);setSampleCount(1);}
void RetroplasmaItem::setController(RetroplasmaController *controller){if(m_controller==controller)return;QObject::disconnect(m_updateConnection);m_controller=controller;if(controller){m_updateConnection=connect(controller,&RetroplasmaController::renderChanged,this,[this](){update();});controller->setViewport(width(),height());}emit controllerChanged();update();}
QQuickRhiItemRenderer *RetroplasmaItem::createRenderer(){return new Renderer;}
void RetroplasmaItem::geometryChange(const QRectF &now,const QRectF &before){QQuickRhiItem::geometryChange(now,before);if(m_controller)m_controller->setViewport(now.width(),now.height());}

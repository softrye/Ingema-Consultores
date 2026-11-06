// Vector PDF port of exportPdf.ts using the exact same CalicataExportPages
// depth fragments as the native XLSX. A3 landscape, 60 rows x 0.05 m.
namespace {
struct WebPdfGeometry {
    double rowY[91]{};
    double colX[57]{};
    double scale = 1.0;
    QRectF cell(int r1,int c1,int r2,int c2) const {
        return QRectF(colX[c1],rowY[r1],
                      colX[c2+1]-colX[c1],rowY[r2+1]-rowY[r1]);
    }
};
WebPdfGeometry webPdfGeometry()
{
    WebPdfGeometry g;
    constexpr double w=1190.55, h=841.89;
    double heights[90]{};
    double sum=0.0;
    for (int row=1;row<=89;++row) {
        double pt=15.75;
        if (row>=22 && row<=81) pt=21.75;
        switch(row) {
        case 6:pt=50.25;break;case 7:pt=10.15;break;
        case 8:case 9:case 10:case 11:case 12:pt=30.0;break;
        case 13:case 14:pt=16.5;break;case 18:pt=30.0;break;
        case 19:pt=15.0;break;case 20:pt=45.75;break;
        case 21:pt=10.5;break;case 82:pt=21.75;break;
        case 83:pt=19.9;break;
        case 84:case 85:case 86:case 87:case 88:case 89:pt=25.15;break;
        default:break;
        }
        heights[row]=pt;sum+=pt;
    }
    const double top=0.5905511811023623*72.0;
    const double bottom=0.1968503937007874*72.0;
    g.scale=(h-top-bottom)/sum;
    g.rowY[1]=top;
    for (int r=1;r<=89;++r)g.rowY[r+1]=g.rowY[r]+heights[r]*g.scale;
    QVector<double> widths(56,6.7109375);
    auto span=[&](int first,int last,double value) {
        for(int c=first;c<=last;++c)widths[c]=value;
    };
    span(1,1,3.140625);span(2,3,2.7109375);span(4,4,5.7109375);
    span(5,5,1.42578125);span(6,6,1.28515625);span(7,7,6);
    span(8,8,7.140625);span(9,9,1.7109375);span(10,10,6.28515625);
    span(11,11,15.7109375);span(12,12,11.28515625);
    span(13,13,15.5703125);span(14,16,15.7109375);
    span(17,17,5.28515625);span(18,21,3.42578125);
    span(22,25,4.28515625);span(26,29,3.42578125);
    span(30,30,7.28515625);span(31,31,13.7109375);
    span(32,32,10.7109375);span(33,33,11.7109375);
    span(34,34,8.7109375);span(35,35,11.140625);
    span(36,36,8.7109375);span(37,37,9.28515625);
    span(38,38,9.7109375);span(39,41,6.7109375);
    span(42,42,11);span(43,45,6.7109375);span(46,46,17.28515625);
    span(47,48,4.28515625);span(49,49,7.42578125);
    span(50,50,27);span(51,51,30.5703125);
    span(52,52,25.5703125);span(53,53,16);
    span(54,54,8.140625);span(55,55,9.28515625);
    double total=0;
    for(int c=1;c<=55;++c)total+=widths[c];
    const double unit=5.25*g.scale;
    g.colX[1]=(w-total*unit)/2.0;
    for(int c=1;c<=55;++c)g.colX[c+1]=g.colX[c]+widths[c]*unit;
    return g;
}
void webPdfBox(QPainter &p, const QRectF &r, QColor color={})
{
    p.save();
    p.setPen(QPen(QColor(QStringLiteral("#202020")),0.4));
    p.setBrush(color.isValid()?QBrush(color):QBrush(Qt::NoBrush));
    p.drawRect(r);
    p.restore();
}
void webPdfText(QPainter &p, const QRectF &r, const QString &value,
                qreal px=7.0, bool bold=false, bool rotated=false,
                QColor ink=QColor(QStringLiteral("#111827")))
{
    if (value.trimmed().isEmpty() || r.isEmpty())return;
    p.save();
    QFont f(QStringLiteral("Arial"));
    f.setBold(bold);p.setPen(ink);
    const QRectF target = rotated
        ? QRectF(-r.height()/2.0,-r.width()/2.0,r.height(),r.width()).adjusted(1,1,-1,-1)
        : r.adjusted(2,1,-2,-1);
    const int flags = Qt::AlignCenter | Qt::TextWordWrap;
    // Fit text to its actual box instead of silently painting at a fixed
    // size. The same policy applies to both normal and rotated cell labels.
    for(int size=std::max(3,int(px));size>=3;--size) {
        f.setPixelSize(size);p.setFont(f);
        const QRectF needed=p.fontMetrics().boundingRect(target.toRect(),flags,value);
        if(needed.width()<=target.width()+1.0 && needed.height()<=target.height()+1.0)break;
    }
    if(rotated){p.translate(r.center());p.rotate(-90);}
    p.drawText(target,flags,value);
    p.restore();
}
void webPdfImage(QPainter &p, const QRectF &r, const QImage &image, double inset=0.04)
{
    if(image.isNull() || r.width()<=0 || r.height()<=0)return;
    p.save();p.setRenderHint(QPainter::SmoothPixmapTransform,true);
    const QRectF frame=r.adjusted(r.width()*inset,r.height()*inset,
                                  -r.width()*inset,-r.height()*inset);
    QSizeF fit=image.size();fit.scale(frame.size(),Qt::KeepAspectRatio);
    const QRectF placed(frame.center().x()-fit.width()/2.,frame.center().y()-fit.height()/2.,
                        fit.width(),fit.height());
    p.drawImage(placed,image);p.restore();
}
bool paintWebCalicataPdfPage(QPainter &p, const WebPdfGeometry &g,
                            const QVariantMap &state,const ReportImages &images,
                            const CalicataExportPages::Page &page, QString *error)
{
    const QVariantMap header=headerFromState(state);
    const QVariantMap stamp=state.value(QStringLiteral("timestamp")).toMap();
    const QString code=canonicalCalicataCode(header,stamp);
    QString title=firstText(header,{QStringLiteral("title"),QStringLiteral("description"),
                                    QStringLiteral("excel_title")});
    if(title.isEmpty())title=code.isEmpty()?QStringLiteral("CALICATA"):code;
    const QColor navy(QStringLiteral("#151A30")), green(QStringLiteral("#486426"));
    const QColor group(QStringLiteral("#DFE8F3")), sub(QStringLiteral("#E8EEE0"));
    const QColor pale(QStringLiteral("#F2F6FB")), dark(QStringLiteral("#1F2937"));
    auto box=[&](int r1,int c1,int r2,int c2,QColor fill={}) {
        const auto rect=g.cell(r1,c1,r2,c2);webPdfBox(p,rect,fill);return rect;
    };
    auto field=[&](int row,int c1,int c2,int v1,int v2,const QString &label,const QString &value){
        webPdfText(p,box(row,c1,row,c2,pale),label,6,true);
        webPdfText(p,box(row,v1,row,v2,pale),value,6);
    };

    webPdfText(p,box(1,33,3,55,navy),QStringLiteral("TESTIFICACIÓN DE CALICATA"),
               13,true,false,QColor(Qt::white));
    webPdfText(p,box(4,33,6,55,green),title,11,true,false,QColor(Qt::white));
    webPdfBox(p,g.cell(1,2,12,15));
    webPdfBox(p,g.cell(1,16,12,32));
    webPdfImage(p,g.cell(1,2,12,15),images[1],0.10);
    webPdfImage(p,g.cell(1,16,12,32),images[0],0.10);
    field(9,34,35,36,42,QStringLiteral("Supervisor:"),firstText(header,{QStringLiteral("supervisor")}));
    field(10,34,35,36,42,QStringLiteral("Máquina:"),firstText(header,{QStringLiteral("maquina"),QStringLiteral("machine")}));
    field(11,34,35,36,42,QStringLiteral("Ubicación:"),firstText(header,{QStringLiteral("ubicacion"),QStringLiteral("tramo")}));
    field(8,44,45,46,46,QStringLiteral("P.K.:"),canonicalPk(header));
    field(9,44,45,46,46,QStringLiteral("X UTM:"),firstText(header,{QStringLiteral("utm_x"),QStringLiteral("longitud")}));
    field(10,44,45,46,46,QStringLiteral("Y UTM:"),firstText(header,{QStringLiteral("utm_y"),QStringLiteral("latitud")}));
    field(11,44,45,46,46,QStringLiteral("Z:"),firstText(header,{QStringLiteral("utm_z"),QStringLiteral("altitud")}));
    field(8,47,50,51,52,QStringLiteral("Fecha inicio:"),formatDateForTemplate(firstText(header,{QStringLiteral("fecha_inicio")})));
    field(9,47,50,51,52,QStringLiteral("Fecha fin:"),formatDateForTemplate(firstText(header,{QStringLiteral("fecha_fin")})));
    field(10,47,50,51,52,QStringLiteral("Zona:"),firstText(header,{QStringLiteral("zona")}));
    field(11,47,50,51,52,QStringLiteral("Calicata:"),code);
    webPdfText(p,box(8,53,8,55,pale),QStringLiteral("HOJA"),6,true);
    webPdfText(p,box(9,53,9,55),QString::number(page.number),7);
    webPdfText(p,box(10,53,10,55,pale),QStringLiteral("DE"),6,true);
    webPdfText(p,box(11,53,11,55),QString::number(page.count),7);

    struct Label{int c1,c2;const char* name;};
    static const Label groups[]={
      {2,4,"PROF.\n(m)"},{5,9,"PERFIL ESTRATIGRÁFICO\nSUCS / AASHTO"},
      {10,16,"DESCRIPCIÓN DEL TERRENO"},{17,17,"N.F. (m)"},
      {18,21,"HUMEDAD"},{22,25,"EXCAVABILIDAD"},
      {26,29,"CONSISTENCIA / COMPACTACIÓN"},{30,32,"MUESTRAS / ENSAYOS"},
      {33,33,"AASHTO"},{34,34,"SUCS"},{35,46,"ENSAYOS DE LABORATORIO"},
      {47,55,"FOTOGRAFÍAS DE LA CALICATA"}
    };
    for(const Label &l:groups) {
        const int last=(l.c1>=18&&l.c1<=32)||l.c1==35?15:20;
        webPdfText(p,box(13,l.c1,last,l.c2,group),
                   QString::fromUtf8(l.name),7,true);
    }
    static const char* options[]={
      "Seco","Bajo","Medio","Agua","Rend. bajo","Rend. medio",
      "Rend. alto","Rend. muy alto","Suelto","Med. denso","Rígido","Muy rígido"};
    for(int i=0;i<12;++i)
        webPdfText(p,box(16,18+i,20,18+i,pale),QString::fromUtf8(options[i]),7,false,true);
    static const char* labheads[]={"TIPO","INTERVALO","RESULTADOS"};
    for(int i=0;i<3;++i)
        webPdfText(p,box(16,30+i,20,30+i,pale),QString::fromUtf8(labheads[i]),7,false,true);
    static const char* labels[]={"MAX","2 mm","0.4 mm","0.08 mm","N.º 4",
                                 "WL","LP","HUM.","I.P.","LAB.","FECHA","—"};
    for(int i=0;i<12;++i)
        webPdfText(p,box(16,35+i,20,35+i,pale),QString::fromUtf8(labels[i]),7,false,true);

    for(int row=22;row<=81;++row) {
        webPdfBox(p,g.cell(row,2,row,4));
        webPdfBox(p,g.cell(row,5,row,46));
        if((row-22)%10==0)
            webPdfText(p,g.cell(row,3,row,4),
                       QString::number(double(page.originCm+(row-22)*5)/100.,'f',2),6);
    }
    webPdfText(p,box(82,3,82,4),
               QString::number(double(page.originCm+300)/100.,'f',2),6);

    for(const CalicataExportPages::Fragment &f:page.fragments) {
        const auto &row=f.row;
        const auto soil=g.cell(f.firstRow,5,f.lastRow,9);
        webPdfBox(p,soil);
        const ExportClassification cls=exportClassificationFor(row);
        const auto hatch=[&](const QString &code,int firstCol,int lastCol) {
            const QRectF region=g.cell(f.firstRow,firstCol,f.lastRow,lastCol);
            const QImage tile=webGraphicExportTile(code);
            if(tile.isNull()) {
                if(error)*error=QStringLiteral("No se pudo cargar el símbolo %1 para el PDF.").arg(code);
                return false;
            }
            const QSize pixels(std::max(1,int(region.width()*3)),
                               std::max(1,int(region.height()*3)));
            const QImage pattern=tiledProfilePattern(tile,pixels,0.5);
            if(pattern.isNull()) {
                if(error)*error=QStringLiteral("No se pudo generar el símbolo %1 para el PDF.").arg(code);
                return false;
            }
            p.drawImage(region,pattern);
            webPdfBox(p,region);
            return true;
        };
        for(const ExportGraphicBand &band:exportGraphicBandsFor(cls)) {
            if(!hatch(band.key,band.firstColumn,band.lastColumn))return false;
        }
        QStringList desc;
        if(f.continuesAbove())
            desc<<QStringLiteral("viene de la hoja %1 ▲").arg(page.number-1)
                <<QStringLiteral("(continuación del Corte %1 · %2–%3 m)")
                  .arg(f.sequence).arg(double(f.fullFromCm)/100.,0,'f',2)
                  .arg(double(f.fullToCm)/100.,0,'f',2);
        desc<<QStringLiteral("%1 m").arg(double(f.toCm-f.fromCm)/100.,0,'f',2);
        if(f.partCount>1)
            desc<<QStringLiteral("parte %1 de %2 · total %3 m")
                .arg(f.partNumber).arg(f.partCount).arg(double(f.fullToCm-f.fullFromCm)/100.,0,'f',2);
        const QString description=firstText(row,{QStringLiteral("descripcion")});
        if(!description.isEmpty())desc<<description;
        const QString colorNote=firstText(row,{QStringLiteral("color_label"),QStringLiteral("colorText"),QStringLiteral("color")});
        if(!colorNote.isEmpty())desc<<QStringLiteral("Color: ")+colorNote;
        const QString layerNotes=firstText(row,{QStringLiteral("observaciones"),QStringLiteral("observations")});
        if(!layerNotes.isEmpty())desc<<QStringLiteral("Observaciones: ")+layerNotes;
        if(f.continuesBelow())
            desc<<QStringLiteral("continúa en la hoja %1 ▼").arg(page.number+1);
        webPdfText(p,box(f.firstRow,10,f.lastRow,16),desc.join(QLatin1Char('\n')),
                   f.lastRow-f.firstRow<4?5:7);
        const int condition[]={humedadIndex(row),excavabilidadIndex(row),webConsistencyIndex(row)};
        for(int band=0;band<3;++band)
            for(int index=0;index<4;++index)
                webPdfBox(p,g.cell(f.firstRow,18+band*4+index,
                                   f.lastRow,18+band*4+index),
                          condition[band]==index?dark:QColor());
        const QString sample=corteText(row,{QStringLiteral("tipo_muestra"),QStringLiteral("muestra"),QStringLiteral("tipoText")},QStringLiteral("txtTipo"));
        webPdfText(p,box(f.firstRow,30,f.lastRow,30),sample,6);
        webPdfText(p,box(f.firstRow,31,f.lastRow,31),
                   QStringLiteral("%1–%2").arg(double(f.fullFromCm)/100.,0,'f',2)
                                     .arg(double(f.fullToCm)/100.,0,'f',2),6);
        webPdfText(p,box(f.firstRow,32,f.lastRow,32),
                   corteText(row,{QStringLiteral("resultado"),QStringLiteral("resultados")}),6);
        webPdfText(p,box(f.firstRow,33,f.lastRow,33),cls.aashto,6);
        webPdfText(p,box(f.firstRow,34,f.lastRow,34),cls.label,6,true);
        static const char *labKeys[]={"gmax","g2","g04","g008","passing_no4",
                                     "wl","lp","hum2","ip","laboratory_source","test_date","reserved"};
        for(int k=0;k<12;++k) {
            QString value=f.firstPart()?corteText(row,{QString::fromLatin1(labKeys[k])}):QString();
            if(k==8 && value.isEmpty() && f.firstPart()) {
                double wl=0,lp=0;
                if(isSimpleNumber(firstText(row,{QStringLiteral("wl")}),&wl) &&
                   isSimpleNumber(firstText(row,{QStringLiteral("lp")}),&lp))
                    value=QString::number(wl-lp,'f',2);
            }
            if((k<5 || k==7) && !value.isEmpty()) {
                double percentage=0;
                if(percentageNumber(value,&percentage))
                    value=QString::number(percentage*100.0,'f',k==0?0:k==7?2:1)+QLatin1Char('%');
            }
            webPdfText(p,box(f.firstRow,35+k,f.lastRow,35+k),value,5,false,k<9);
        }
    }
    if(page.lastDataRow()>=22) {
        const QString groundwater=firstText(header,{QStringLiteral("water_table_depth"),QStringLiteral("groundwater_depth_m")});
        const QString label=groundwater.isEmpty()?QStringLiteral("N.F. GENERAL · NO REGISTRADO")
                           :QStringLiteral("N.F. GENERAL · %1 m BAJO SUPERFICIE").arg(groundwater);
        webPdfText(p,box(22,17,page.lastDataRow(),17,QColor(QStringLiteral("#EEF2E6"))),
                   label,6,true,true);
    }
    if(page.closingRow()>=22&&page.closingRow()<=82)
        webPdfText(p,box(page.closingRow(),18,page.closingRow(),46,sub),
                   QStringLiteral("FIN DE LA CALICATA — %1 m").arg(double(page.totalCm)/100.,0,'f',2),
                   7,true);
    QString obs=structuredObservations(header,double(page.totalCm)/100.,
                                       state.value(QStringLiteral("observaciones")).toString());
    const QString project=exportProjectName(header,stamp);
    if(!project.isEmpty())obs+=QLatin1Char('\n')+project;
    webPdfText(p,box(84,34,89,55),obs,7,true);
    webPdfText(p,box(84,4,86,14),QStringLiteral("MA: MUESTRA ALTERADA"),6,true);
    webPdfText(p,box(84,16,86,26),QStringLiteral("MS: MUESTRA EN SACO"),6,true);
    webPdfText(p,box(87,4,89,14),QStringLiteral("MI: MUESTRA INALTERADA"),6,true);
    webPdfText(p,box(87,16,89,26),QStringLiteral("MW: MUESTRA AGUA"),6,true);

    static const char* photos[]={"Zona de ejecución","Interior de calicata","Acopios"};
    for(int i=0;i<3;++i) {
        const int first=i==0?22:(i==1?43:63);
        const int last=i==0?41:(i==1?61:81);
        webPdfBox(p,g.cell(first,47,last,55));
        webPdfImage(p,g.cell(first,47,last,55),images[i+2],0.04);
        const int caption=i==0?42:(i==1?62:83);
        webPdfText(p,box(caption,47,caption,55,sub),QString::fromUtf8(photos[i]),7);
    }
    return true;
}
QString renderWebCalicataPdf(const QVariantMap &state, const QString &resourcesBase,
                            const QString &exportDirectory, const QString &safeCode,
                            QString *error)
{
    const QVariantMap header=headerFromState(state);
    const QVector<CalicataExportPages::Page> pages =
        CalicataExportPages::paginate(header,cortesFromState(state),error);
    if(pages.isEmpty())return {};
    ReportImages images;
    if(!prepareReportImages(state,resourcesBase,&images,error))return {};
    // El nombre seguro se calcula en AndroidCalicataExporter, donde existe
    // safeFileName(); el renderer libre recibe el resultado, no invoca
    // métodos privados del exportador.
    const QString code=safeCode;
    const QByteArray hash=QCryptographicHash::hash(
        QJsonDocument::fromVariant(state).toJson(QJsonDocument::Compact),QCryptographicHash::Sha256).toHex().left(20);
    const QString outPath=QDir(exportDirectory).filePath(code+QLatin1Char('_')+QString::fromLatin1(hash)+QStringLiteral(".pdf"));
    // Never return a cached PDF generated by the previous A4 renderer.
    // Regenerate atomically so identical state still receives the new A3 layout.
    if(!QDir().mkpath(QFileInfo(outPath).absolutePath())) {
        if(error)*error=QStringLiteral("No se pudo crear la carpeta del PDF.");return {};
    }
    QSaveFile output(outPath);
    if(!output.open(QIODevice::WriteOnly)) {
        if(error)*error=QStringLiteral("No se pudo iniciar el archivo PDF: ")+output.errorString();
        return {};
    }
    QPdfWriter pdf(&output);
    pdf.setPageSize(QPageSize(QPageSize::A3));
    pdf.setPageOrientation(QPageLayout::Landscape);
    pdf.setPageMargins(QMarginsF(0,0,0,0),QPageLayout::Millimeter);
    pdf.setResolution(150);
    pdf.setTitle(QStringLiteral("Calicata ")+code);
    pdf.setCreator(QStringLiteral("InGe+ Android (contrato Web)"));
    QPainter painter;
    if(!painter.begin(&pdf)) {
        if(error)*error=QStringLiteral("No se pudo iniciar el motor PDF.");
        return {};
    }
    painter.setRenderHint(QPainter::Antialiasing,true);
    painter.setRenderHint(QPainter::TextAntialiasing,true);
    painter.scale(double(pdf.width())/1190.55,double(pdf.height())/841.89);
    const WebPdfGeometry geometry=webPdfGeometry();
    for(int index=0;index<pages.size();++index) {
        if(index>0 && !pdf.newPage()) {
            painter.end();
            if(error)*error=QStringLiteral("Error generando la página PDF %1.").arg(index+1);
            return {};
        }
        painter.fillRect(QRectF(0,0,1190.55,841.89),Qt::white);
        if(!paintWebCalicataPdfPage(painter,geometry,state,images,pages[index],error)) {
            painter.end();
            return {};
        }
    }
    painter.end();
    if(!output.commit()) {
        if(error)*error=QStringLiteral("No se pudo guardar el PDF: ")+output.errorString();
        return {};
    }
    return outPath;
}
} // namespace

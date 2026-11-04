// InGe+ Qt/QXlsx port of web exportExcel.ts + exportLayout.ts (04-11-2026).
// The Web creates each worksheet from scratch. DO NOT reuse the old
// Calicata_Formato_Paginado.xlsx: its stale merges, fonts, glyphs and pictures
// are the root cause of the mismatching Android XLSX.
// This file is included once from androidcalicataexporter.cpp under INGE_HAS_QXLSX.
// PDF deliberately keeps its independent, already validated renderer.

QXlsx::Format webPageCell(QColor background = {}, bool bold = false,
                          int fontSize = 8, bool rotate = false)
{
    QXlsx::Format fmt;
    fmt.setFontName(QStringLiteral("Calibri"));
    fmt.setFontSize(fontSize);
    fmt.setFontBold(bold);
    fmt.setFontColor(QColor(QStringLiteral("#111827")));
    fmt.setTextWrap(true);
    fmt.setHorizontalAlignment(QXlsx::Format::AlignHCenter);
    fmt.setVerticalAlignment(QXlsx::Format::AlignVCenter);
    fmt.setBorderStyle(QXlsx::Format::BorderThin);
    fmt.setBorderColor(QColor(QStringLiteral("#202020")));
    if (background.isValid()) {
        fmt.setFillPattern(QXlsx::Format::PatternSolid);
        fmt.setPatternForegroundColor(background);
    }
    if (rotate) fmt.setRotation(90);
    return fmt;
}

QXlsx::Format webNoBorder(QColor background = {}, int fontSize = 8)
{
    auto fmt = webPageCell(background, false, fontSize);
    fmt.setBorderStyle(QXlsx::Format::BorderNone);
    return fmt;
}

// ExcelJS's put() merges before writing. All source worksheet ranges match
// exportExcel.ts (1-based Excel coordinates, not pixel approximations).
bool webPageWrite(QXlsx::Document &xlsx, int top, int left, int bottom, int right,
                  const QVariant &value, const QXlsx::Format &fmt, QString *error)
{
    if (top < 1 || left < 1 || bottom < top || right < left) {
        if (error) *error = QStringLiteral("Rango Excel inválido.");
        return false;
    }
    if ((top != bottom || left != right) &&
        !xlsx.mergeCells(QXlsx::CellRange(top, left, bottom, right), fmt)) {
        if (error) *error = QStringLiteral("No se pudo combinar Excel %1:%2.")
            .arg(QXlsx::CellReference(top, left).toString(),
                 QXlsx::CellReference(bottom, right).toString());
        return false;
    }
    if (!xlsx.write(top, left, value, fmt)) {
        if (error) *error = QStringLiteral("No se pudo escribir Excel %1.")
            .arg(QXlsx::CellReference(top, left).toString());
        return false;
    }
    return true;
}

// This follows the Web outline(): draw only the perimeter of each block,
// NOT a 0.05 m horizontal line through every soil-description row.
void webSheetOutline(QXlsx::Document &xlsx, int c1, int c2, int r1, int r2)
{
    for (int col = c1; col <= c2; ++col) {
        for (int row = r1; row <= r2; ++row) {
            if (col != c1 && col != c2 && row != r1 && row != r2) continue;
            QXlsx::Format fmt = formatAt(xlsx, row, col);
            if (!fmt.isValid()) fmt = webNoBorder();
            if (col == c1) fmt.setLeftBorderStyle(QXlsx::Format::BorderThin);
            if (col == c2) fmt.setRightBorderStyle(QXlsx::Format::BorderThin);
            if (row == r1) fmt.setTopBorderStyle(QXlsx::Format::BorderThin);
            if (row == r2) fmt.setBottomBorderStyle(QXlsx::Format::BorderThin);
            xlsx.write(row, col, xlsx.read(row, col), fmt);
        }
    }
}

void webSheetGeometry(QXlsx::Document &xlsx)
{
    struct Span { int from, to; double width; };
    // exportLayout.ts CALICATA_SHEET_COLUMNS, 55 columns A..BC.
    static const Span spans[] = {
        {1,1,3.140625}, {2,3,2.7109375}, {4,4,5.7109375},
        {5,5,1.42578125}, {6,6,1.28515625}, {7,7,6.0},
        {8,8,7.140625}, {9,9,1.7109375}, {10,10,6.28515625},
        {11,11,15.7109375}, {12,12,11.28515625}, {13,13,15.5703125},
        {14,16,15.7109375}, {17,17,5.28515625}, {18,21,3.42578125},
        {22,25,4.28515625}, {26,29,3.42578125},
        {30,30,7.28515625}, {31,31,13.7109375},
        {32,32,10.7109375}, {33,33,11.7109375},
        {34,34,8.7109375}, {35,35,11.140625},
        {36,36,8.7109375}, {37,37,9.28515625},
        {38,38,9.7109375}, {39,41,6.7109375},
        {42,42,11.0}, {43,45,6.7109375}, {46,46,17.28515625},
        {47,48,4.28515625}, {49,49,7.42578125},
        {50,50,27.0}, {51,51,30.5703125}, {52,52,25.5703125},
        {53,53,16.0}, {54,54,8.140625}, {55,55,9.28515625}
    };
    for (const auto &span : spans)
        xlsx.setColumnWidth(span.from, span.to, span.width);
    xlsx.setRowHeight(1, 89, 15.75);
    const std::pair<int, double> special[] = {
        {6,50.25},{7,10.15},{8,30},{9,30},{10,30},{11,30},
        {12,30},{13,16.5},{14,16.5},{15,15},{16,15},
        {17,15},{18,30},{19,15},{20,45.75},{21,10.5},
        {82,21.75},{83,19.9},{84,25.15},{85,25.15},{86,25.15},
        {87,25.15},{88,25.15},{89,25.15}
    };
    for (const auto &pair : special) xlsx.setRowHeight(pair.first, pair.second);
    xlsx.setRowHeight(22, 81, 21.75);
    if (auto *sheet = xlsx.currentWorksheet()) {
        sheet->setGridLinesVisible(false);
        sheet->setCalicataA3PrintLayout();
    }
}

int webConsistencyIndex(const QVariantMap &row)
{
    const QString consistency = firstText(row, {
        QStringLiteral("consistency_compaction"),QStringLiteral("consistencia"),
        QStringLiteral("estabilidad")}).toUpper();
    if (consistency.contains(QStringLiteral("SUELTO"))) return 0;
    if (consistency.contains(QStringLiteral("MEDIAN"))) return 1;
    if (consistency.contains(QStringLiteral("MUY_RIG"))) return 3;
    if (consistency.contains(QStringLiteral("RIG"))) return 2;
    return estabilidadIndex(row);
}

bool fillWebPaginatedSheet(QXlsx::Document &xlsx, const QVariantMap &state,
                           const ReportImages &images,
                           const CalicataExportPages::Page &page, QString *error)
{
    const QString sheetName = QStringLiteral("Calicata %1").arg(page.number);
    if (!xlsx.selectSheet(sheetName)) {
        if (error) *error = QStringLiteral("No se creó la hoja Excel: ") + sheetName;
        return false;
    }
    webSheetGeometry(xlsx);
    const QColor titleBlue(QStringLiteral("#151A30"));
    const QColor projectGreen(QStringLiteral("#486426"));
    const QColor group(QStringLiteral("#DFE8F3"));
    const QColor subgroup(QStringLiteral("#E8EEE0"));
    const QColor option(QStringLiteral("#F2F6FB"));
    const QColor active(QStringLiteral("#1F2937"));

    const QVariantMap header=headerFromState(state);
    const QVariantMap timestamp=state.value(QStringLiteral("timestamp")).toMap();
    const QString code=canonicalCalicataCode(header,timestamp);
    const QString project=exportProjectName(header,timestamp);
    QString title=firstText(header, {QStringLiteral("title"),QStringLiteral("description"),
                                     QStringLiteral("excel_title")});
    if(title.isEmpty())title=code.isEmpty()?QStringLiteral("CALICATA"):code;

    const auto put=[&](int r1,int c1,int r2,int c2,const QVariant &v,
                       const QXlsx::Format &f){
        return webPageWrite(xlsx,r1,c1,r2,c2,v,f,error);
    };
    auto base=webPageCell({},false,10);
    auto head=webPageCell(group,true,10);
    head.setFontName(QStringLiteral("Utsaah"));
    auto headLarge=webPageCell(group,true,14);
    headLarge.setFontName(QStringLiteral("Utsaah"));
    auto light=webPageCell(option,false,11);
    auto headerLabel=webPageCell(option,true,11);
    auto band=webPageCell(option,false,12,true);

    // Web exportExcel.ts writeTitle(): the title occupies only AG:BC.
    auto titleFmt=webPageCell(titleBlue,true,26);
    titleFmt.setFontName(QStringLiteral("Arial Narrow"));
    titleFmt.setFontColor(Qt::white);
    if(!put(1,33,3,55,QStringLiteral("TESTIFICACIÓN DE CALICATA"),titleFmt))return false;
    auto projectFmt=webPageCell(projectGreen,true,projectTitleFontSize(title));
    projectFmt.setFontName(QStringLiteral("Arial Narrow"));
    projectFmt.setFontColor(Qt::white);
    if(!put(4,33,6,55,title,projectFmt))return false;
    webSheetOutline(xlsx,33,55,1,6);

    // Logos are *pictures*, not merged cells. No inherited characters or fills.
    webSheetOutline(xlsx,2,15,1,12);
    webSheetOutline(xlsx,16,32,1,12);

    auto field=[&](int r,int c1,int c2,int v1,int v2,
                   const QString &label,const QString &value){
        return put(r,c1,r,c2,label,headerLabel) &&
               put(r,v1,r,v2,value,light);
    };
    // Exact Web header blocks. Blank fields stay blank rather than invented.
    if(!field(9,34,35,36,42,QStringLiteral("Supervisor:"),
              firstText(header,{QStringLiteral("supervisor")}))) return false;
    if(!field(10,34,35,36,42,QStringLiteral("Máquina:"),
              firstText(header,{QStringLiteral("maquina"),QStringLiteral("machine")})))return false;
    if(!field(11,34,35,36,42,QStringLiteral("Ubicación:"),
              firstText(header,{QStringLiteral("ubicacion"),QStringLiteral("tramo"),QStringLiteral("location")})))return false;
    if(!field(8,44,45,46,46,QStringLiteral("P.K.:"),canonicalPk(header)))return false;
    const QString coordinateSystem=firstText(header,{
        QStringLiteral("coordinate_system"),QStringLiteral("coordinateSystem")}).toUpper();
    const bool utm=coordinateSystem.isEmpty() || coordinateSystem.contains(QStringLiteral("UTM"));
    if(!field(9,44,45,46,46,utm?QStringLiteral("X UTM:"):QStringLiteral("Coord. 1:"),
              firstText(header,{QStringLiteral("utm_x"),QStringLiteral("easting"),QStringLiteral("longitud")})))return false;
    if(!field(10,44,45,46,46,utm?QStringLiteral("Y UTM:"):QStringLiteral("Coord. 2:"),
              firstText(header,{QStringLiteral("utm_y"),QStringLiteral("northing"),QStringLiteral("latitud")})))return false;
    if(!field(11,44,45,46,46,QStringLiteral("Z:"),
              firstText(header,{QStringLiteral("utm_z"),QStringLiteral("altitud")})))return false;
    if(!field(8,47,50,51,52,QStringLiteral("Fecha inicio:"),
              formatDateForTemplate(firstText(header,{QStringLiteral("fecha_inicio"),QStringLiteral("start_date")}))))return false;
    if(!field(9,47,50,51,52,QStringLiteral("Fecha fin:"),
              formatDateForTemplate(firstText(header,{QStringLiteral("fecha_fin"),QStringLiteral("end_date")}))))return false;
    if(!field(10,47,50,51,52,QStringLiteral("Zona:"),
              firstText(header,{QStringLiteral("zona"),QStringLiteral("utm_zone")})))return false;
    if(!field(11,47,50,51,52,QStringLiteral("Calicata:"),code))return false;
    if(!put(8,53,8,55,QStringLiteral("HOJA"),headerLabel) ||
       !put(9,53,9,55,QString::number(page.number),base) ||
       !put(10,53,10,55,QStringLiteral("DE"),headerLabel) ||
       !put(11,53,11,55,QString::number(page.count),base))return false;
    webSheetOutline(xlsx,34,43,8,11);
    webSheetOutline(xlsx,44,46,8,11);
    webSheetOutline(xlsx,47,50,8,11);
    webSheetOutline(xlsx,51,52,8,11);
    webSheetOutline(xlsx,53,55,8,11);

    // Web writeGridHeaders(): correct non-overlapping bands (no legacy header).
    auto stacked=[&](int c1,int c2,const QString &label,int size){
        QXlsx::Format fmt=webPageCell(group,true,size);
        fmt.setFontName(QStringLiteral("Utsaah"));
        return put(13,c1,20,c2,label,fmt);
    };
    if(!stacked(2,4,QStringLiteral("PROF.\n(m)"),14) ||
       !stacked(5,9,QStringLiteral("PERFIL"),14) ||
       !stacked(10,16,QStringLiteral("DESCRIPCIÓN DEL TERRENO"),20) ||
       !stacked(17,17,QStringLiteral("N.F. (m)"),14))return false;
    struct LabelGroup { int first,last;const char *name; };
    static const LabelGroup bands[]={
        {18,21,"HUMEDAD"},{22,25,"EXCAVABILIDAD"},
        {26,29,"CONSISTENCIA / COMPACTACIÓN"}
    };
    for (const auto &b:bands)
        if(!put(13,b.first,15,b.last,QString::fromUtf8(b.name),head))return false;
    static const char *options[]={
       "Seco","Bajo","Medio","Agua",
       "Rend. bajo","Rend. medio","Rend. alto","Rend. muy alto",
       "Suelto","Medianamente denso","Rígido","Muy rígido"
    };
    for(int i=0;i<12;++i)
        if(!put(16,18+i,20,18+i,QString::fromUtf8(options[i]),band))return false;
    if(!put(13,30,15,32,QStringLiteral("MUESTRAS / ENSAYOS"),head))return false;
    const QStringList samples={QStringLiteral("TIPO"),QStringLiteral("INTERVALO (m)"),
                               QStringLiteral("RESULTADOS")};
    for(int i=0;i<3;++i)
        if(!put(16,30+i,20,30+i,samples.at(i),band))return false;
    auto rotatedGroup=webPageCell(group,true,12,true);
    if(!put(13,33,20,33,QStringLiteral("CLASIFICACIÓN AASHTO"),rotatedGroup) ||
       !put(13,34,20,34,QStringLiteral("CLASIFICACIÓN SUCS"),rotatedGroup))return false;
    if(!put(13,35,15,46,QStringLiteral("ENSAYOS DE LABORATORIO"),head))return false;
    auto subhead=webPageCell(subgroup,true,12);
    if(!put(16,35,17,39,QStringLiteral("GRANULOMETRÍA (%)"),subhead) ||
       !put(16,40,17,41,QStringLiteral("PLASTICIDAD"),subhead) ||
       !put(16,42,17,42,QStringLiteral("ESTADO NATURAL"),subhead) ||
       !put(16,43,17,46,QStringLiteral("CLASIFICACIÓN Y LABORATORIO"),subhead))return false;
    const QStringList sieves={
        QStringLiteral("máx."),QStringLiteral("2 mm"),QStringLiteral("0.4 mm"),
        QStringLiteral("0.08 mm"),QStringLiteral("N.º 4")
    };
    for(int i=0;i<5;++i)
        if(!put(18,35+i,20,35+i,sieves.at(i),band))return false;
    const QStringList laboratory={
        QStringLiteral("WL"),QStringLiteral("LP"),QStringLiteral("Humedad"),
        QStringLiteral("I.P."),QStringLiteral("Lab."),QStringLiteral("Fecha"),QStringLiteral("—")
    };
    for(int i=0;i<7;++i)
        if(!put(18,40+i,20,40+i,laboratory.at(i),band))return false;
    if(!put(13,47,20,55,QStringLiteral("FOTOGRAFÍAS DE LA CALICATA"),headLarge))return false;

    // Depth axis: merges C:D on all 60 rows, labels every 0.50 m.
    auto scale=webNoBorder({},11);
    scale.setHorizontalAlignment(QXlsx::Format::AlignRight);
    for(int row=22;row<=81;++row) {
        const int offsetCm=(row-22)*5;
        const QString text=(offsetCm%50)==0
            ? QString::number(double(page.originCm+offsetCm)/100.0,'f',2)
            : QString();
        if(!put(row,3,row,4,text,scale))return false;
        QXlsx::Format tick=webNoBorder();
        tick.setTopBorderStyle(QXlsx::Format::BorderThin);
        xlsx.write(row,2,QVariant(),tick);
    }
    if(!put(82,3,82,4,
            QString::number(double(page.originCm+300)/100.0,'f',2),scale))return false;
    webSheetOutline(xlsx,2,4,22,81);
    const int endRow=page.lastDataRow();
    if(endRow>=22)webSheetOutline(xlsx,5,46,22,endRow);

    // Web writeFragment(): one merged block per stratum and per option.
    for (const CalicataExportPages::Fragment &fragment:page.fragments) {
        const QVariantMap &row=fragment.row;
        const int first=fragment.firstRow,last=fragment.lastRow;
        QStringList description;
        if(fragment.continuesAbove()) {
            description<<QStringLiteral("viene de la hoja %1 ▲").arg(page.number-1)
                <<QStringLiteral("(continuación del Corte %1 · %2–%3 m)")
                    .arg(fragment.sequence)
                    .arg(double(fragment.fullFromCm)/100.,0,'f',2)
                    .arg(double(fragment.fullToCm)/100.,0,'f',2);
        }
        description<<QStringLiteral("%1 m")
            .arg(double(fragment.toCm-fragment.fromCm)/100.,0,'f',2);
        if(fragment.partCount>1)
            description<<QStringLiteral("parte %1 de %2 · total %3")
                .arg(fragment.partNumber).arg(fragment.partCount)
                .arg(double(fragment.fullToCm-fragment.fullFromCm)/100.,0,'f',2);
        const QString text=corteText(row,{QStringLiteral("descripcion")},QStringLiteral("txtDescripcion"));
        if(!text.isEmpty())description<<text;
        const QString origin=firstText(row,{QStringLiteral("material_origin")});
        if(!origin.isEmpty())description<<origin;
        const QString colorNote=firstText(row,{QStringLiteral("color_label"),QStringLiteral("colorText")});
        if(!colorNote.isEmpty())description<<QStringLiteral("Color: ")+colorNote;
        const QString notes=firstText(row,{QStringLiteral("observaciones"),QStringLiteral("observations")});
        if(!notes.isEmpty())description<<QStringLiteral("Observaciones: ")+notes;
        if(fragment.continuesBelow())description<<QStringLiteral("continúa en la hoja %1 ▼").arg(page.number+1);
        auto descFmt=webPageCell({},false,last-first>=7?11:last-first>=3?9:8);
        if(!put(first,10,last,16,description.join(QLatin1Char('\n')),descFmt))return false;

        const int selected[]={humedadIndex(row),excavabilidadIndex(row),webConsistencyIndex(row)};
        for(int groupIndex=0;groupIndex<3;++groupIndex)
            for(int k=0;k<4;++k)
                if(!put(first,18+groupIndex*4+k,last,18+groupIndex*4+k,QVariant(),
                        webPageCell(selected[groupIndex]==k?active:QColor(),false,8)))return false;

        const ExportClassification cls=exportClassificationFor(row);
        const QString kind=corteText(row,{QStringLiteral("tipo_muestra"),QStringLiteral("muestra"),
                                           QStringLiteral("tipoText")},QStringLiteral("txtTipo"));
        if(!put(first,30,last,30,kind,base))return false;
        if(!put(first,31,last,31,
                QStringLiteral("%1–%2").arg(double(fragment.fullFromCm)/100.,0,'f',2)
                                         .arg(double(fragment.fullToCm)/100.,0,'f',2),base))return false;
        if(!put(first,32,last,32,
                corteText(row,{QStringLiteral("resultado"),QStringLiteral("resultados")}),base))return false;
        if(!put(first,33,last,33,cls.aashto,base))return false;
        auto sucsFmt=webPageCell({},true,10);
        if(!put(first,34,last,34,cls.label,sucsFmt))return false;

        // Web lab cells: five granulo percentages, WL, LP, moisture, IP,
        // lab source, test date, and blank column AT. Continuations keep
        // SUCS/AASHTO but do not duplicate numeric lab measurements.
        static const char *keys[12]={
          "gmax","g2","g04","g008","passing_no4","wl","lp","hum2","ip",
          "laboratory_source","test_date","reserved"
        };
        for(int i=0;i<12;++i) {
            QString value=fragment.firstPart()
                 ?corteText(row,{QString::fromLatin1(keys[i])}):QString();
            if(i==8 && value.isEmpty() && fragment.firstPart()) {
                double wl=0,lp=0;
                if(isSimpleNumber(firstText(row,{QStringLiteral("wl")}),&wl) &&
                   isSimpleNumber(firstText(row,{QStringLiteral("lp")}),&lp))
                    value=QString::number(wl-lp,'f',2);
            }
            QXlsx::Format fmt=webPageCell({},false,10);
            QVariant converted=value;
            if(i<5 || i==7) {
                fmt.setNumberFormat(i==0?QStringLiteral("0%")
                                    : i==7?QStringLiteral("0.00%"):QStringLiteral("0.0%"));
                double pct=0;
                converted=percentageNumber(value,&pct)?QVariant(pct):QVariant();
            } else if(i>=5 && i<=8) {
                fmt.setNumberFormat(QStringLiteral("0.0"));
                bool ok=false;QString s=value;s.replace(QLatin1Char(','),QLatin1Char('.'));
                const double n=s.toDouble(&ok);
                converted=ok?QVariant(n):QVariant(value);
            }
            if(!put(first,35+i,last,35+i,converted,fmt))return false;
        }

        // Web's profile uses only E:I (E:G + H:I for composite SUCS).
        const QString colorText=firstText(row,{
            QStringLiteral("color_hex"),QStringLiteral("colorHex"),QStringLiteral("color")});
        const QColor background(colorText);
        const QColor soilFill=background.isValid()?background:QColor(QStringLiteral("#F8FAFC"));
        const auto drawRegion=[&](const QString &sucs,int from,int to,bool pattern) {
            if(!put(first,from,last,to,QVariant(),webNoBorder(soilFill)))return false;
            webSheetOutline(xlsx,from,to,first,last);
            if(!pattern || sucs.isEmpty())return true;
            const QImage tile=webSucsExportTile(sucs);
            if(tile.isNull()) {
                if(error)*error=QStringLiteral("No existe la trama SUCS ")+sucs;
                return false;
            }
            const QSize boxSize(rangeWidthPixels(xlsx,from,to),
                                rangeHeightPixels(xlsx,first,last));
            QImage image=tiledProfilePattern(tile,boxSize,0.5);
            if(image.isNull())return false;
            // The Web rasterizer writes the thickness inside the hatch.
            QPainter painter(&image);
            painter.setPen(QColor(QStringLiteral("#111827")));
            QFont font(QStringLiteral("Arial"));
            font.setPixelSize(std::max(12,boxSize.height()/7));
            font.setBold(true);painter.setFont(font);
            painter.drawText(image.rect(),Qt::AlignCenter,
                QStringLiteral("%1 m").arg(double(fragment.toCm-fragment.fromCm)/100.,0,'f',2));
            painter.end();
            if(!insertImageFitted(xlsx,first,from,last,to,image,true)) {
                if(error)*error=QStringLiteral("Error en la trama SUCS del corte %1")
                    .arg(fragment.sequence);
                return false;
            }
            return true;
        };
        if(cls.secondary.isEmpty()) {
            if(!drawRegion(cls.primary,5,9,true))return false;
        } else {
            if(!drawRegion(cls.primary,5,7,true) ||
               !drawRegion(cls.secondary,8,9,true))return false;
        }
    }

    // General groundwater box ends on the last measured row, as on the Web.
    if(endRow>=22) {
        const QString depth=firstText(header,{
            QStringLiteral("water_table_depth"),QStringLiteral("water_table_depth_m"),
            QStringLiteral("groundwater_depth_m")});
        const int count=endRow-21;
        QString groundwater;
        if(count<8)groundwater=QStringLiteral("N.F.");
        else if(count<24) groundwater=depth.isEmpty()
            ?QStringLiteral("N.F. NO REG."):QStringLiteral("N.F. %1 m").arg(depth);
        else groundwater=depth.isEmpty()
            ?QStringLiteral("N.F. GENERAL · NO REGISTRADO")
            :QStringLiteral("N.F. GENERAL · %1 m BAJO SUPERFICIE").arg(depth);
        if(!put(22,17,endRow,17,groundwater,
                webPageCell(QColor(QStringLiteral("#EEF2E6")),true,9,true)))return false;
    }
    if(page.closingRow()>=22 && page.closingRow()<=82)
        if(!put(page.closingRow(),18,page.closingRow(),46,
                QStringLiteral("FIN DE LA CALICATA — %1 m")
                    .arg(double(page.totalCm)/100.0,0,'f',2),
                webPageCell(subgroup,true,8)))return false;

    // Web writeClosing(): observations and four legend blocks on B:AG.
    QStringList obs{QStringLiteral("OBSERVACIONES")};
    const QString note=firstText(header,{
        QStringLiteral("observaciones"),QStringLiteral("observations")});
    obs<<(note.isEmpty()?QStringLiteral("Sin observaciones registradas."):note);
    if(!project.isEmpty())obs<<project;
    if(firstText(header,{QStringLiteral("utm_x"),QStringLiteral("utm_y"),
                         QStringLiteral("latitud"),QStringLiteral("longitud")}).isEmpty())
        obs<<QStringLiteral("Sin coordenadas registradas.");
    const QString waterDepth=firstText(header,{
        QStringLiteral("water_table_depth"),QStringLiteral("water_table_depth_m"),
        QStringLiteral("groundwater_depth_m")});
    obs<< (waterDepth.isEmpty() ?QStringLiteral("Nivel freático general: No registrado")
                                 :QStringLiteral("Nivel freático general: %1 m bajo superficie").arg(waterDepth));
    auto obsFmt=webPageCell({},true,8);
    obsFmt.setHorizontalAlignment(QXlsx::Format::AlignLeft);
    obsFmt.setVerticalAlignment(QXlsx::Format::AlignTop);
    if(!put(84,34,89,55,obs.join(QLatin1Char('\n')),obsFmt))return false;
    webSheetOutline(xlsx,2,33,84,89);
    auto legend=webPageCell({},true,8);
    if(!put(84,4,86,14,QStringLiteral("MA: MUESTRA ALTERADA"),legend) ||
       !put(84,16,86,26,QStringLiteral("MS: MUESTRA EN SACO"),legend) ||
       !put(87,4,89,14,QStringLiteral("MI: MUESTRA INALTERADA"),legend) ||
       !put(87,16,89,26,QStringLiteral("MW: MUESTRA AGUA"),legend))return false;

    // Images: logos on B:O and P:AF, photos on AU:BC, each page.
    if(!images[1].isNull() &&
       !insertImageFitted(xlsx,1,2,12,15,images[1],false)) {
        if(error)*error=QStringLiteral("No se pudo colocar el logo del proyecto.");
        return false;
    }
    if(!images[0].isNull() &&
       !insertImageFitted(xlsx,1,16,12,32,images[0],false)) {
        if(error)*error=QStringLiteral("No se pudo colocar el logo de la entidad.");
        return false;
    }
    static const int photos[][2]={{22,41},{43,61},{63,81}};
    static const char* captions[]={
        "Zona de ejecución","Interior de calicata","Acopios"
    };
    for(int i=0;i<3;++i) {
        const int from=photos[i][0],to=photos[i][1];
        webSheetOutline(xlsx,47,55,from,to);
        if(!images[i+2].isNull() &&
           !insertImageFitted(xlsx,from,47,to,55,images[i+2],false)) {
            if(error)*error=QStringLiteral("No se pudo colocar fotografía %1.").arg(i+1);
            return false;
        }
        auto captionFmt=webPageCell(subgroup,false,12);
        if(!put(to+1,47,to+1,55,QString::fromUtf8(captions[i]),captionFmt))return false;
    }

    if(!xlsx.defineName(QStringLiteral("_xlnm.Print_Area"),
                        QStringLiteral("'%1'!$B$1:$BC$89").arg(sheetName),
                        QString(),sheetName)) {
        if(error)*error=QStringLiteral("No se pudo configurar la impresión de ")+sheetName;
        return false;
    }
    return true;
}

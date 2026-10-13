#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QVariantList>
#include <QFileSystemModel>
#include <QDir>
#include <QUrl>

class DocsController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString basePath READ basePath NOTIFY basePathChanged)
    Q_PROPERTY(QString resourcesPath READ resourcesPath NOTIFY basePathChanged)
    Q_PROPERTY(bool hasClipboard READ hasClipboard NOTIFY clipboardChanged)

public:
    explicit DocsController(QObject *parent = nullptr);

    QString basePath() const { return m_basePath; }

    // ✅ Evita "Recursos" relativo cuando basePath está vacío
    QString resourcesPath() const {
        if (m_basePath.trimmed().isEmpty()) return {};
        return QDir(m_basePath).absoluteFilePath(kResourcesFolderName);
    }

    bool hasClipboard() const { return !m_clipboardPath.isEmpty(); }

    // ---------- Root por usuario ----------
    Q_INVOKABLE QVariantMap applyUserRoot(bool logged,
                                          const QString& userId,
                                          const QString& displayName,
                                          const QString& globalBasePath);

    // ---------- Capabilities ----------
    Q_INVOKABLE QVariantMap capabilities(const QString& selectedAbsPath) const;

    // ---------- Clipboard ----------
    Q_INVOKABLE void copyToClipboard(const QString& absPath);
    Q_INVOKABLE QVariantMap cutToClipboard(const QString& absPath);
    Q_INVOKABLE QVariantMap pasteInto(const QString& targetDirAbs);

    // ---------- File ops ----------
    Q_INVOKABLE QVariantMap newFolder(const QString& parentDirAbs,
                                      const QString& baseName = QStringLiteral("Nueva carpeta"));
    Q_INVOKABLE QVariantMap removePaths(const QStringList& absPaths);
    Q_INVOKABLE QVariantMap renamePath(const QString& absPath, const QString& newName);

    // ---------- Define / Remove metas ----------
    Q_INVOKABLE QVariantMap defineProject(const QString& folderAbs,
                                          const QString& projectName,
                                          const QString& clientName);
    Q_INVOKABLE QVariantMap removeProject(const QString& folderAbs);

    Q_INVOKABLE QVariantMap defineEditable(const QString& folderAbs, bool allowReplaceExisting = true);
    Q_INVOKABLE QVariantMap removeEditable(const QString& folderAbs);

    Q_INVOKABLE QVariantMap defineCalicatas(const QString& folderAbs);
    Q_INVOKABLE QVariantMap removeCalicatas(const QString& folderAbs);

    Q_INVOKABLE QVariantMap defineExcel(const QString& folderAbs);
    Q_INVOKABLE QVariantMap removeExcel(const QString& folderAbs);

    Q_INVOKABLE QVariantMap definePdf(const QString& folderAbs);
    Q_INVOKABLE QVariantMap removePdf(const QString& folderAbs);

    // ---------- Recursos ----------
    Q_INVOKABLE QVariantMap importImagesToResources(const QStringList& absFiles);

    // ---------- Editable: logos compartidos ----------
    Q_INVOKABLE QString resolveEditableFolderFromAnyPath(const QString& anyAbsPath) const;

    Q_INVOKABLE QVariantMap getEditableSharedLogos(const QString& editableFolderAbs) const;
    Q_INVOKABLE QVariantMap setEditableSharedLogos(const QString& editableFolderAbs,
                                                   const QString& mtcRel,
                                                   const QString& proyectoRel,
                                                   bool applyToAllFiles = true);

    Q_INVOKABLE int countCalicataFilesToPatch(const QString& editableFolderAbs) const;

    // ---------- Utilidad ----------
    Q_INVOKABLE QString fileKind(const QString& absPath) const;
    Q_INVOKABLE QStringList listFilesRecursively(const QString& rootAbs) const;
    Q_INVOKABLE QString relativePath(const QString& absPath, const QString& baseAbs) const;

    // --- ASYNC: para abrir dialog sin congelar ---
    Q_INVOKABLE void requestEditableLogosDialogData(const QString& anyAbsPath, int token);

    // --- ASYNC: aplicar (patch masivo) sin congelar ---
    Q_INVOKABLE void setEditableSharedLogosAsync(const QString& editableFolderAbs,
                                                 const QString& mtcRel,
                                                 const QString& proyectoRel,
                                                 bool applyToAllFiles,
                                                 int token);

    Q_INVOKABLE QString getEditableTitle(const QString& editableFolder);
    Q_INVOKABLE bool setEditableTitle(const QString& editableFolder, const QString& title);

    // ---------- Proyecto: leer/editar + warning al quitar ----------
    Q_INVOKABLE QVariantMap getProjectInfo(const QString& projectFolderAbs) const;

    // Reporte para advertencia antes de quitar proyecto
    Q_INVOKABLE QString projectRemovalReport(const QString& folderAbs) const;

    // Quita proyecto y (opcional) limpia metas especiales internas
    Q_INVOKABLE QVariantMap removeProjectWithCleanup(const QString& projectFolderAbs,
                                                     bool cleanupNestedSpecial = true);


    Q_INVOKABLE QString folderSpecialKind(const QString& absPath) const;

    Q_INVOKABLE bool containsCalicatasMeta(const QString& dirAbs) const;
    Q_INVOKABLE bool containsProjectMeta(const QString& dirAbs) const;


    bool isLevel1Folder(const QString& folderAbs) const;
    bool isResourcesRootFolder(const QString& folderAbs) const;

    QVariantMap scanSpecialMetasInTree(const QString& projRootAbs) const;
    QVariantMap clearSpecialMetasInTree(const QString& projRootAbs) const;

    // Si las llamas desde QML -> Q_INVOKABLE
    Q_INVOKABLE QVariantMap removeCalicatasWithCleanup(const QString& folderAbs,
                                                       bool cleanupNestedSpecial);

    Q_INVOKABLE QString calicatasRemovalReport(const QString& folderAbs) const;



    QString findSingleMetaFolderUnderDirectChildren(const QString& root, const char* metaFile) const;


    // ---- Calicata files ----
    Q_INVOKABLE QVariantMap createCalicataFile(const QString& targetDirAbs,
                                               const QString& baseName,
                                               bool overwrite = false) const;

    Q_INVOKABLE bool isCalicataFile(const QString& absPath) const;

    Q_INVOKABLE QVariantMap validatePlacement(const QString& sourceAbsPath,
                                              const QString& targetDirAbs) const;

signals:
    void basePathChanged();
    void clipboardChanged();

    void editableSharedLogosChanged(const QString& editableFolderAbs,
                                    const QString& mtcRel,
                                    const QString& proyectoRel);
    void editableLogosDialogDataReady(int token, bool ok,
                                      const QString& editableFolderAbs,
                                      const QString& mtcRel,
                                      const QString& proRel,
                                      int filesToPatch,
                                      const QString& err);

    void editableSharedLogosApplied(int token, bool ok,
                                    int updated, int failed,
                                    const QString& firstError,
                                    const QString& err);

private:
    // ================== Constantes (AJUSTA si difieren) ==================
    static constexpr const char* kResourcesFolderName = "Recursos";
    static constexpr const char* kEditablePhotosFolder = "fotos";

    static constexpr const char* kProjectMetaFile   = ".ingep_project.json";
    static constexpr const char* kEditableMetaFile  = ".ingep_editable.json";
    static constexpr const char* kCalicatasMetaFile = ".ingep_calicatas.json";
    static constexpr const char* kExcelMetaFile     = ".ingep_excel.json";
    static constexpr const char* kPdfMetaFile       = ".ingep_pdf.json";
    static constexpr const char* kResourcesMetaFile = ".ingep_resources.json";

    static constexpr const char* kCalicatasEditFolder  = "Edit";
    static constexpr const char* kCalicatasExcelFolder = "EXCEL";
    static constexpr const char* kCalicatasPdfFolder   = "PDF";

    // ✅ ahora soporta file:///...
    static QString clean(const QString& p) {
        QString s = p.trimmed();
        if (s.isEmpty()) return {};

        if (s.startsWith("file:", Qt::CaseInsensitive)) {
            QUrl u(s);
            if (u.isValid() && u.isLocalFile()) {
                const QString lf = u.toLocalFile();
                if (!lf.isEmpty()) s = lf;
            }
        }

        s = QDir::fromNativeSeparators(s);
        while (s.startsWith("./")) s.remove(0, 2);
        return QDir::cleanPath(s);
    }

    static QString sanitizeFolderName(QString s);

    bool ensureResourcesFolder() const;

    bool isUnderResourcesPath(const QString& absPath) const;
    bool isProtectedResourcesFile(const QString& absPath) const;

    bool isImageFile(const QString& absPath) const;
    bool isExcelFile(const QString& absPath) const;
    bool isPdfFile(const QString& absPath) const;

    // ---- Meta checks ----
    bool isProjectFolder(const QString& folderAbs) const;
    bool isEditableFolder(const QString& folderAbs) const;
    bool isCalicatasFolder(const QString& folderAbs) const;
    bool isExcelFolder(const QString& folderAbs) const;
    bool isPdfFolder(const QString& folderAbs) const;

    QString findMetaUp(const QString& startAbs, const char* metaFile) const;
    bool isInsideProject(const QString& anyAbs, QString* outProjectRoot) const;
    bool canDefineProjectHere(const QString& folderAbs) const;

    QString findSingleMetaFolderUnder(const QString& root, const char* metaFile) const;
    QString findCalicatasFolderInProject(const QString& projRoot) const;
    QString findEditableFolderInProject(const QString& projRoot) const;

    bool canDefineCalicatasHere(const QString& folderAbs) const;
    bool canDefineExcelHere(const QString& folderAbs) const;
    bool canDefinePdfHere(const QString& folderAbs) const;

    // ---- Meta write/remove ----
    bool writeJsonMeta(const QString& folderAbs, const char* metaFile, const QVariantMap& fields) const;
    bool removeMeta(const QString& folderAbs, const char* metaFile) const;

    bool ensureEditablePhotosDir(const QString& editableFolderAbs) const;
    bool ensureCalicatasStructure(const QString& calicatasFolderAbs) const;

    // ---- FS ops ----
    bool copyDirRecursively(const QString& srcPath, const QString& dstPath) const;
    bool dirContainsMetaRecursively(const QString& dirAbs, const char* metaFile) const;
    bool dirContainsProjectMetaRecursively(const QString& dirAbs) const;

    QString uniqueNameForPaste(const QString& targetDirAbs, const QString& baseName) const;

    // ---- Editable logos patch ----
    bool readEditableSharedLogos(const QString& editableFolderAbs,
                                 QString& outMtcRel,
                                 QString& outProyectoRel) const;

    bool writeEditableSharedLogos(const QString& editableFolderAbs,
                                  const QString& mtcRel,
                                  const QString& proyectoRel) const;

    // ---- Editable title (excel_title) ----
    bool readEditableTitle(const QString& editableFolderAbs,
                           QString& outTitle) const;

    bool writeEditableTitle(const QString& editableFolderAbs,
                            const QString& title) const;


    static bool patchCalicataFileLogosOnDisk(const QString& filePath,
                                             const QString& mtcRel,
                                             const QString& proyectoRel,
                                             QString* err);

    void applyEditableLogosToAllCalicataFiles(const QString& editableFolderAbs,
                                              const QString& mtcRel,
                                              const QString& proyectoRel,
                                              int* outUpdated,
                                              int* outFailed,
                                              QStringList* outErrors) const;
    // helpers internos
    bool isInsideCalicatas(const QString& anyAbs, QString* outCalRoot = nullptr) const;


private:
    QString m_basePath;
    QString m_clipboardPath;
    bool    m_cutOperation = false;
};

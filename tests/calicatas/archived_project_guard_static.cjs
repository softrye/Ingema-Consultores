// Regression: an active membership in an ARCHIVADO project is NOT write access.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8').replace(/\r\n/g, '\n');
const cloud = read('calicatacloudservice.cpp');
const form = read('qml/Mobile/pages/CalicataFormPage.qml');
const editor = read('qml/Mobile/pages/CalicatasEditorPage.qml');

const refresh = cloud.slice(cloud.indexOf('void CalicataCloudService::refreshProjects()'),
                            cloud.indexOf('void CalicataCloudService::listProjectCalicatas('));
assert.match(refresh, /list_my_project_memberships_v01/);
assert.match(refresh, /restUrl\(QStringLiteral\("projects"\)\)/);
assert.match(refresh, /QStringLiteral\("id,status"\)/);
assert.match(refresh, /m_projectsRefreshPending = false/);
assert.match(refresh, /status != QLatin1String\("ARCHIVADO"\)/);
assert.match(refresh, /if \(status\.isEmpty\(\)\) continue/);

const sync = cloud.slice(cloud.indexOf('QString CalicataCloudService::syncDocument('),
                         cloud.indexOf('void CalicataCloudService::patchRemoteStatus('));
assert.match(sync, /archivedProject/);
assert.match(sync, /QLatin1String\("ARCHIVADO"\)/);
assert.match(sync, /el borrador local se conserva/);

const picker = form.slice(form.indexOf('function _applyProjectSelection(project)'),
                          form.indexOf('id: projectPickerPopup'));
assert.match(picker, /project\.writable === false/);
assert.match(picker, /root\.doc\.selectProject\(selection\)/);
assert.ok(picker.indexOf('project.writable === false') < picker.indexOf('root.doc.selectProject(selection)'));
assert.match(form, /Archivado \(solo lectura\)/);
const create = editor.slice(editor.indexOf('function createFromHome(v)'),
                            editor.indexOf('// Fondo real de la subapp'));
assert.match(create, /project\.writable === false/);
assert.ok(create.indexOf('project.writable === false') < create.indexOf('root.addNewTab()'));
assert.match(create, /proyecto activo con permisos de escritura/);

console.log('PASS: archived project is read-only; local drafts and server authorization remain unchanged');
(() => {
  'use strict';

  const DB_NAME = 'inge_earth';
  const DB_VERSION = 1;
  const PROJECTS = 'projects';
  const BLOBS = 'project_blobs';
  const SETTINGS = 'settings';
  let databasePromise;

  const request = (operation) => new Promise((resolve, reject) => {
    operation.onsuccess = () => resolve(operation.result);
    operation.onerror = () => reject(operation.error || new Error('INDEXEDDB_REQUEST_FAILED'));
  });

  const transactionDone = (transaction) => new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onabort = () => reject(transaction.error || new Error('INDEXEDDB_TRANSACTION_ABORTED'));
    transaction.onerror = () => reject(transaction.error || new Error('INDEXEDDB_TRANSACTION_FAILED'));
  });

  const open = () => {
    if (databasePromise)
      return databasePromise;
    databasePromise = new Promise((resolve, reject) => {
      const operation = indexedDB.open(DB_NAME, DB_VERSION);
      operation.onupgradeneeded = () => {
        const database = operation.result;
        if (!database.objectStoreNames.contains(PROJECTS))
          database.createObjectStore(PROJECTS, { keyPath: 'id' });
        if (!database.objectStoreNames.contains(BLOBS))
          database.createObjectStore(BLOBS, { keyPath: 'id' });
        if (!database.objectStoreNames.contains(SETTINGS))
          database.createObjectStore(SETTINGS, { keyPath: 'key' });
      };
      operation.onsuccess = () => {
        const database = operation.result;
        database.onversionchange = () => database.close();
        resolve(database);
      };
      operation.onerror = () => {
        databasePromise = null;
        reject(operation.error || new Error('INDEXEDDB_OPEN_FAILED'));
      };
    });
    return databasePromise;
  };

  const run = async (stores, mode, callback) => {
    const database = await open();
    const transaction = database.transaction(stores, mode);
    const result = await callback(transaction);
    await transactionDone(transaction);
    return result;
  };

  const migrateProject = (value) => {
    if (!value || value.schemaVersion !== 1)
      throw new Error('PROJECT_SCHEMA_UNSUPPORTED');
    return value;
  };

  const listProjects = async () => {
    const database = await open();
    const items = await request(database.transaction(PROJECTS, 'readonly').objectStore(PROJECTS).getAll());
    return items.map(migrateProject).sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt)));
  };

  const getProject = async (id) => {
    if (!id)
      return null;
    const database = await open();
    const value = await request(database.transaction(PROJECTS, 'readonly').objectStore(PROJECTS).get(id));
    return value ? migrateProject(value) : null;
  };

  const putProject = (project) => run([PROJECTS], 'readwrite', (transaction) => {
    if (!project || project.schemaVersion !== 1 || !project.id)
      throw new Error('PROJECT_INVALID');
    transaction.objectStore(PROJECTS).put(project);
  });

  const deleteProject = (project) => run([PROJECTS, BLOBS, SETTINGS], 'readwrite', (transaction) => {
    transaction.objectStore(PROJECTS).delete(project.id);
    (project.imports || []).forEach((item) => {
      if (item.blobId)
        transaction.objectStore(BLOBS).delete(item.blobId);
    });
    transaction.objectStore(SETTINGS).put({ key: 'activeProjectId', value: null });
  });

  const putBlob = (id, blob, metadata) => run([BLOBS], 'readwrite', (transaction) => {
    transaction.objectStore(BLOBS).put({ id, blob, metadata: metadata || {}, updatedAt: new Date().toISOString() });
  });

  const getBlob = async (id) => {
    if (!id)
      return null;
    const database = await open();
    const value = await request(database.transaction(BLOBS, 'readonly').objectStore(BLOBS).get(id));
    return value || null;
  };

  const deleteBlob = (id) => run([BLOBS], 'readwrite', (transaction) => {
    transaction.objectStore(BLOBS).delete(id);
  });

  const setSetting = (key, value) => run([SETTINGS], 'readwrite', (transaction) => {
    transaction.objectStore(SETTINGS).put({ key, value });
  });

  const getSetting = async (key, fallback) => {
    const database = await open();
    const value = await request(database.transaction(SETTINGS, 'readonly').objectStore(SETTINGS).get(key));
    return value ? value.value : fallback;
  };

  window.InGeEarthStorage = {
    open,
    listProjects,
    getProject,
    putProject,
    deleteProject,
    putBlob,
    getBlob,
    deleteBlob,
    setSetting,
    getSetting
  };
})();

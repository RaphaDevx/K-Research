const { app, BrowserWindow, Menu, dialog, ipcMain } = require('electron');
const { autoUpdater } = require('electron-updater');
const path = require('path');

let mainWindow;

// ── Auto-Updater Config ────────────────────────────────────────────────────────
autoUpdater.autoDownload = false;      // ask user first
autoUpdater.autoInstallOnAppQuit = true;

autoUpdater.on('update-available', (info) => {
  dialog.showMessageBox(mainWindow, {
    type: 'info',
    title: 'Update verfügbar',
    message: `K-Research ${info.version} ist verfügbar.`,
    detail: `Aktuelle Version: ${app.getVersion()}\nNeue Version: ${info.version}\n\nJetzt herunterladen?`,
    buttons: ['Jetzt aktualisieren', 'Später'],
    defaultId: 0,
    cancelId: 1,
  }).then(({ response }) => {
    if (response === 0) autoUpdater.downloadUpdate();
  });
});

autoUpdater.on('download-progress', (progress) => {
  if (mainWindow) {
    mainWindow.setProgressBar(progress.percent / 100);
    mainWindow.setTitle(`K-Research — Download ${Math.round(progress.percent)}%`);
  }
});

autoUpdater.on('update-downloaded', (info) => {
  if (mainWindow) {
    mainWindow.setProgressBar(-1);
    mainWindow.setTitle('K-Research');
  }
  dialog.showMessageBox(mainWindow, {
    type: 'info',
    title: 'Update bereit',
    message: `K-Research ${info.version} wurde heruntergeladen.`,
    detail: 'Jetzt neu starten und installieren?',
    buttons: ['Neu starten', 'Später'],
    defaultId: 0,
    cancelId: 1,
  }).then(({ response }) => {
    if (response === 0) autoUpdater.quitAndInstall();
  });
});

autoUpdater.on('error', (err) => {
  // Silent — don't annoy user with update errors on launch
  console.error('[updater]', err.message);
});

autoUpdater.on('update-not-available', () => {
  console.log('[updater] Up to date:', app.getVersion());
});

// ── Window ────────────────────────────────────────────────────────────────────
function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    minWidth: 900,
    minHeight: 600,
    backgroundColor: '#0a0a0a',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 16 },
    webPreferences: {
      webSecurity: false,
      allowFileAccessFromFileURLs: true,
      nodeIntegration: false,
      contextIsolation: true,
    },
    icon: path.join(__dirname, 'assets', 'icon.icns'),
  });

  mainWindow.loadFile('index.html');

  Menu.setApplicationMenu(Menu.buildFromTemplate([
    {
      label: 'K-Research',
      submenu: [
        { label: 'Über K-Research', role: 'about' },
        {
          label: `Version ${app.getVersion()}`,
          enabled: false,
        },
        { type: 'separator' },
        {
          label: 'Nach Updates suchen…',
          click: () => autoUpdater.checkForUpdates(),
        },
        { type: 'separator' },
        { label: 'Beenden', accelerator: 'Cmd+Q', click: () => app.quit() },
      ],
    },
    {
      label: 'Bearbeiten',
      submenu: [
        { role: 'undo' }, { role: 'redo' }, { type: 'separator' },
        { role: 'cut' }, { role: 'copy' }, { role: 'paste' },
      ],
    },
    {
      label: 'Ansicht',
      submenu: [
        { role: 'reload' },
        { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
      ],
    },
  ]));
}

// ── App lifecycle ─────────────────────────────────────────────────────────────
app.whenReady().then(() => {
  createWindow();

  // Check for updates 3 seconds after launch (only in packaged app)
  if (app.isPackaged) {
    setTimeout(() => autoUpdater.checkForUpdates(), 3000);
  }

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

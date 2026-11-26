const {contextBridge,ipcRenderer}=require('electron');contextBridge.exposeInMainWorld('proxyHelper',{run:(action,proxy)=>ipcRenderer.invoke('action',action,proxy)});

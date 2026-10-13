import React from 'react';
// Reuse the existing Android web glass resource, then apply the InGeCoreFlow tokens.
import '../../../../assets/cesium/ui/inge-earth-ui.css';
import { createRoot } from 'react-dom/client';
import App from '../App';
createRoot(document.getElementById('root')!).render(<App />);

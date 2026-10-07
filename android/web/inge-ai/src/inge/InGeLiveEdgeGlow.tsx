// Halo perimetral de InGe+ IA (estado visual activo, estilo Gemini Live).
//
// Solo presentación: no conoce Gemini, el bridge ni permisos. Vive mientras
// exista la consola, es decir, mientras el host mantenga el WebView de la IA
// (GeminiAssistant.active); al cerrar, el host destruye el WebView y con él
// esta capa. Animación 100 % CSS compuesta en GPU (transform/opacity): sin
// requestAnimationFrame, sin canvas, sin timers y sin re-render de React por
// frame. Capas:
//   A rim fino luminoso · B masas de luz que recorren el perímetro ·
//   C bruma interior/exterior · D respiración de intensidad.
// Una máscara radial mantiene el centro de la pantalla limpio.
type EdgeGlowMode = 'idle' | 'voice' | 'thinking';

export default function InGeLiveEdgeGlow({ leaving, mode }: { leaving: boolean; mode: EdgeGlowMode }) {
  return <div className={`inge-edge-glow ${mode}${leaving ? ' leaving' : ''}`} aria-hidden>
    <div className="edge-field">
      <div className="edge-haze" />
      <div className="edge-blobs">
        <i className="edge-blob blob-a" />
        <i className="edge-blob blob-b" />
        <i className="edge-blob blob-c" />
        <i className="edge-blob blob-d" />
      </div>
      <div className="edge-rim rim-blue" />
      <div className="edge-rim rim-green" />
    </div>
  </div>;
}

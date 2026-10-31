/// Installed inside the EmulatorJS page on iOS, where Safari starts
/// AudioContext muted until a user gesture lands in that document.
///
/// The overlay is the gesture. Tapping it resumes every context EmulatorJS
/// is known to keep, then removes itself so the touch controls work.
const String iosEmulatorAudioUnlockScript = r'''
(function () {
  if (window.__mofinAudioGate) return;
  window.__mofinAudioGate = true;
  function resume(ctx) {
    try { if (ctx && ctx.state === 'suspended' && ctx.resume) ctx.resume(); } catch (e) {}
  }
  function resumeAll() {
    var emu = window.EJS_emulator;
    if (emu) {
      resume(emu.audioContext);
      var gm = emu.gameManager;
      if (gm) {
        resume(gm.audioContext);
        var module = gm.Module;
        if (module && module.SDL2) resume(module.SDL2.audioContext);
      }
    }
    if (typeof window.moonfinResumeAudio === 'function') {
      try { window.moonfinResumeAudio(); } catch (e) {}
    }
    var nodes = document.querySelectorAll('audio,video');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      el.muted = false;
      try {
        var p = el.play && el.play();
        if (p && p.catch) p.catch(function () {});
      } catch (e) {}
    }
  }
  var gate = document.createElement('button');
  gate.type = 'button';
  gate.textContent = 'Tap to start';
  gate.setAttribute('aria-label', 'Tap to start');
  gate.style.cssText = 'position:fixed;inset:0;z-index:2147483647;margin:0;border:0;background:rgba(0,0,0,.72);color:#fff;font:600 22px -apple-system,sans-serif;';
  function unlock(event) {
    if (event) { event.preventDefault(); event.stopPropagation(); }
    resumeAll();
    gate.remove();
    document.removeEventListener('pointerdown', unlock, true);
  }
  gate.addEventListener('pointerdown', unlock, true);
  document.addEventListener('pointerdown', unlock, true);
  function mount() {
    var parent = document.body || document.documentElement;
    if (parent) parent.appendChild(gate);
  }
  if (document.body) mount();
  else document.addEventListener('DOMContentLoaded', mount);
})();
''';

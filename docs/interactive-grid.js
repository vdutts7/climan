/**
 * backdrop: cursor-glow - soft radial glow follows pointer (replaces interactive dots)
 * Auto-inits on [data-backdrop-cursor-glow] or .backdrop-cursor-glow
 */
(function (global) {
  'use strict';

  var DEFAULTS = {
    size: 460,
    color: '83, 144, 255',
    opacity: 0.38,
    blur: 52
  };

  function num(el, attr, fallback) {
    var v = el.getAttribute(attr);
    return v != null && v !== '' ? parseFloat(v) : fallback;
  }

  function initHost(host) {
    if (host.dataset.backdropGlowInit) return;
    host.dataset.backdropGlowInit = '1';

    var cfg = {
      size: num(host, 'data-glow-size', DEFAULTS.size),
      color: host.getAttribute('data-glow-color') || DEFAULTS.color,
      opacity: num(host, 'data-glow-opacity', DEFAULTS.opacity),
      blur: num(host, 'data-glow-blur', DEFAULTS.blur)
    };

    var reduced = global.matchMedia('(prefers-reduced-motion: reduce)').matches;

    var orb = host.querySelector('.backdrop-cursor-glow-orb');
    if (!orb) {
      orb = document.createElement('div');
      orb.className = 'backdrop-cursor-glow-orb';
      host.appendChild(orb);
    }

    orb.style.setProperty('--glow-size', cfg.size + 'px');
    orb.style.setProperty('--glow-color', cfg.color);
    orb.style.setProperty('--glow-opacity', String(cfg.opacity));
    orb.style.setProperty('--glow-blur', cfg.blur + 'px');

    var visible = false;
    var x = global.innerWidth * 0.5;
    var y = global.innerHeight * 0.35;

    function place(clientX, clientY) {
      orb.style.transform = 'translate3d(' + clientX + 'px,' + clientY + 'px,0)';
    }

    function show() {
      if (visible) return;
      visible = true;
      host.classList.add('is-active');
    }

    function hide() {
      if (!visible) return;
      visible = false;
      host.classList.remove('is-active');
    }

    function onMove(e) {
      x = e.clientX;
      y = e.clientY;
      place(x, y);
      show();
    }

    function onLeave() {
      hide();
    }

    place(x, y);
    if (reduced) {
      host.classList.add('is-active', 'is-reduced');
      place(global.innerWidth * 0.5, global.innerHeight * 0.28);
    } else {
      global.addEventListener('mousemove', onMove, { passive: true });
      document.documentElement.addEventListener('mouseleave', onLeave);
    }

    host._backdropGlowDestroy = function () {
      global.removeEventListener('mousemove', onMove);
      document.documentElement.removeEventListener('mouseleave', onLeave);
      delete host.dataset.backdropGlowInit;
    };
  }

  function initAll(root) {
    (root || document).querySelectorAll('[data-backdrop-cursor-glow], .backdrop-cursor-glow').forEach(initHost);
  }

  global.BackdropCursorGlow = { init: initHost, initAll: initAll, defaults: DEFAULTS };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { initAll(); });
  } else {
    initAll();
  }
})(window);

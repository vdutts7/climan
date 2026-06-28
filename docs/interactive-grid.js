/**
 * backdrop: interactive-grid — vanilla port of spoonfeeder InteractiveGrid.tsx
 * Auto-inits on [data-backdrop-interactive-grid] or .backdrop-interactive-grid
 */
(function (global) {
  'use strict';

  var DEFAULTS = {
    gridGap: 35,
    dotSize: 1.2,
    radius: 180,
    color: 'rgba(100, 100, 100, 0.15)',
    highlightColor: 'rgba(150, 150, 150, 0.45)'
  };

  function num(el, attr, fallback) {
    var v = el.getAttribute(attr);
    return v != null && v !== '' ? parseFloat(v) : fallback;
  }

  function initHost(host) {
    if (host.dataset.backdropGridInit) return;
    host.dataset.backdropGridInit = '1';

    var cfg = {
      gridGap: num(host, 'data-grid-gap', DEFAULTS.gridGap),
      dotSize: num(host, 'data-dot-size', DEFAULTS.dotSize),
      radius: num(host, 'data-radius', DEFAULTS.radius),
      color: host.getAttribute('data-dot-color') || DEFAULTS.color,
      highlightColor: host.getAttribute('data-dot-highlight') || DEFAULTS.highlightColor
    };

    var reduced = global.matchMedia('(prefers-reduced-motion: reduce)').matches;

    var canvas = host.querySelector('canvas.backdrop-interactive-grid-canvas');
    if (!canvas) {
      canvas = document.createElement('canvas');
      canvas.className = 'backdrop-interactive-grid-canvas';
      host.insertBefore(canvas, host.firstChild);
    }

    var mouse = { x: -1000, y: -1000 };
    var dots = [];
    var raf = 0;

    function initDots(w, h) {
      dots = [];
      var cols = Math.ceil(w / cfg.gridGap) + 1;
      var rows = Math.ceil(h / cfg.gridGap) + 1;
      for (var i = 0; i < cols; i++) {
        for (var j = 0; j < rows; j++) {
          dots.push({ x: i * cfg.gridGap, y: j * cfg.gridGap });
        }
      }
    }

    function resize() {
      var rect = host.getBoundingClientRect();
      canvas.width = Math.max(1, Math.floor(rect.width));
      canvas.height = Math.max(1, Math.floor(rect.height));
      initDots(canvas.width, canvas.height);
      if (reduced) drawOnce();
    }

    function drawOnce() {
      var ctx = canvas.getContext('2d');
      if (!ctx) return;
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      var radiusSq = cfg.radius * cfg.radius;
      for (var i = 0; i < dots.length; i++) {
        var dot = dots[i];
        var dx = dot.x - mouse.x;
        var dy = dot.y - mouse.y;
        var distSq = dx * dx + dy * dy;
        ctx.beginPath();
        if (distSq < radiusSq) {
          var dist = Math.sqrt(distSq);
          var factor = 1 - dist / cfg.radius;
          ctx.arc(dot.x, dot.y, cfg.dotSize + factor * 2, 0, Math.PI * 2);
          ctx.fillStyle = cfg.highlightColor;
        } else {
          ctx.arc(dot.x, dot.y, cfg.dotSize, 0, Math.PI * 2);
          ctx.fillStyle = cfg.color;
        }
        ctx.fill();
      }
    }

    function loop() {
      drawOnce();
      raf = global.requestAnimationFrame(loop);
    }

    function onMove(e) {
      var rect = canvas.getBoundingClientRect();
      mouse.x = e.clientX - rect.left;
      mouse.y = e.clientY - rect.top;
      if (reduced) drawOnce();
    }

    function onLeave() {
      mouse.x = -1000;
      mouse.y = -1000;
      if (reduced) drawOnce();
    }

    resize();
    if (reduced) {
      drawOnce();
    } else {
      raf = global.requestAnimationFrame(loop);
    }

    global.addEventListener('resize', resize);
    canvas.addEventListener('mousemove', onMove);
    canvas.addEventListener('mouseleave', onLeave);

    host._backdropGridDestroy = function () {
      global.removeEventListener('resize', resize);
      canvas.removeEventListener('mousemove', onMove);
      canvas.removeEventListener('mouseleave', onLeave);
      if (raf) global.cancelAnimationFrame(raf);
      delete host.dataset.backdropGridInit;
    };
  }

  function initAll(root) {
    (root || document).querySelectorAll('[data-backdrop-interactive-grid], .backdrop-interactive-grid').forEach(initHost);
  }

  global.BackdropInteractiveGrid = { init: initHost, initAll: initAll, defaults: DEFAULTS };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { initAll(); });
  } else {
    initAll();
  }
})(window);

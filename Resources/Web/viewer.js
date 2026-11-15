/* Native arguments arrive via callAsyncJavaScript; score text is never HTML. */
(() => {
  const score = document.getElementById('score');
  const osmd = new opensheetmusicdisplay.OpenSheetMusicDisplay(score, {
    backend: 'svg', autoResize: false, drawTitle: true, pageFormat: 'A4_P',
    newSystemFromXML: true, newPageFromXML: true
  });
  window.viewer = {
    async load(xml) {
      score.innerHTML = '';
      await osmd.load(xml);
      osmd.Zoom = 1;
      osmd.render();
      if (!score.querySelector('svg')) throw new Error('No pages rendered');
      for (const svg of score.querySelectorAll('svg')) {
        svg.parentElement.classList.add('music-page');
      }
      window.scrollTo(0, 0);
    },
    zoom(value) { score.style.zoom = Math.min(2, Math.max(0.5, value)); }
  };
})();

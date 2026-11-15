/* Native arguments arrive via callAsyncJavaScript; score text is never HTML. */
(() => {
  const score = document.getElementById('score');
  const osmd = new opensheetmusicdisplay.OpenSheetMusicDisplay(score, {
    backend: 'svg', autoResize: false, drawTitle: true, pageFormat: 'A4_P'
  });
  const choices = [0, 2, 3, 4, 6, 8];
  function lineCounts() {
    return osmd.graphic.MusicPages.flatMap(page => page.MusicSystems.map(system =>
      system.StaffLines[0].Measures.filter(measure => !measure.IsExtraGraphicalMeasure).length));
  }
  window.viewer = {
    async load(xml, measures = 4) {
      if (!choices.includes(measures)) throw new Error('Invalid measures per line');
      score.innerHTML = '';
      osmd.setOptions({ newSystemFromXML: measures === 0, newPageFromXML: measures === 0 });
      osmd.EngravingRules.RenderXMeasuresPerLineAkaSystem = measures;
      osmd.EngravingRules.NewPartAndSystemAfterFinalBarline = measures === 0;
      await osmd.load(xml);
      // Engraving scale changes the actual A4 layout, independently of screen zoom.
      // OSMD's measures-per-system rule alone is only a maximum: dense measures
      // still wrap. Reduce notation size until every complete line fits the choice.
      let scale = 1, tooLarge = null;
      for (let attempt = 0; attempt < 9; attempt++) {
        osmd.Zoom = scale;
        osmd.render();
        const lines = lineCounts();
        if (!measures || lines.slice(0, -1).every(count => count === measures)) {
          // Recover some space after the coarse fit, keeping notes as readable as possible.
          if (tooLarge !== null) {
            const fittingScale = scale;
            osmd.Zoom = (scale + tooLarge) / 2;
            osmd.render();
            if (!lineCounts().slice(0, -1).every(count => count === measures)) {
              osmd.Zoom = fittingScale;
              osmd.render();
            }
          }
          break;
        }
        if (scale <= 0.2 || attempt === 8) throw new Error('Score too dense for this layout');
        const shortest = Math.min(...lines.slice(0, -1));
        tooLarge = scale;
        scale = Math.max(0.2, scale * Math.max(0.5, Math.min(0.85, shortest / measures)));
      }
      if (!score.querySelector('svg')) throw new Error('No pages rendered');
      for (const svg of score.querySelectorAll('svg')) svg.parentElement.classList.add('music-page');
      window.scrollTo(0, 0);
      return this.layoutInfo();
    },
    layoutInfo() {
      return { measuresPerLine: lineCounts(), pages: osmd.graphic.MusicPages.length, notationScale: osmd.Zoom };
    },
    zoom(value) { score.style.zoom = Math.min(2, Math.max(0.5, value)); }
  };
})();

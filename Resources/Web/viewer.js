/* OSMD 1.9.2 is bundled and pinned; no score or selection leaves this WebView. */
(() => {
  const score = document.getElementById('score');
  const osmd = new opensheetmusicdisplay.OpenSheetMusicDisplay(score, {
    backend: 'svg', autoResize: false, drawTitle: true, pageFormat: 'A4_P'
  });
  const choices = [0, 2, 3, 4, 6, 8];
  let source, parts = [], selected = [], loadedSelection = null;
  const scales = new Map(), widthsBySelection = new Map();
  let lastTiming = {}, fullDraws = 0, parses = 0;
  function lineCounts() {
    return osmd.graphic.MusicPages.flatMap(page => page.MusicSystems.map(system =>
      system.StaffLines[0].Measures.filter(measure => !measure.IsExtraGraphicalMeasure).length));
  }
  function fits(measures) { return lineCounts().slice(0, -1).every(count => count === measures); }
  function layoutOnly(scale) {
    // Same A4 layout calculation as the pinned OSMD render(), without building
    // thousands of SVG nodes for each trial size. Only the final layout is drawn.
    osmd.Sheet.pageWidth = score.offsetWidth / scale / 10;
    osmd.EngravingRules.PageHeight = osmd.Sheet.pageWidth / osmd.EngravingRules.PageFormat.aspectRatio;
    osmd.graphic.reCalculate();
  }
  function filteredScore(ids) {
    const doc = source.cloneNode(true);
    const chosen = new Set(ids);
    for (const part of doc.querySelectorAll('score-part, score-partwise > part')) {
      if (!chosen.has(part.getAttribute('id'))) part.remove();
    }
    if (ids.length !== parts.length) {
      // Group brackets can refer to removed parts; the selected parts remain complete.
      for (const group of doc.querySelectorAll('part-group')) group.remove();
    }
    return doc;
  }
  window.viewer = {
    async load(xml, measures = 4, ids = null) {
      source = new DOMParser().parseFromString(xml, 'application/xml');
      if (source.querySelector('parsererror')) throw new Error('Invalid score XML');
      parts = [...source.querySelectorAll('part-list > score-part')].map(part => ({
        id: part.getAttribute('id'), name: part.querySelector('part-name')?.textContent?.trim() || part.getAttribute('id')
      }));
      loadedSelection = null;
      scales.clear(); widthsBySelection.clear();
      return this.configure(measures, ids);
    },
    async configure(measures, ids = null) {
      const started = performance.now();
      if (!source || !choices.includes(measures)) throw new Error('Invalid layout');
      const requested = ids === null ? parts.map(part => part.id) : ids;
      if (!Array.isArray(requested) || !requested.length || requested.some(id => !parts.some(part => part.id === id))) throw new Error('Invalid voice selection');
      const selection = parts.map(part => part.id).filter(id => requested.includes(id));
      const selectionKey = JSON.stringify(selection);
      osmd.setOptions({ newSystemFromXML: measures === 0, newPageFromXML: measures === 0 });
      osmd.EngravingRules.RenderXMeasuresPerLineAkaSystem = measures;
      osmd.EngravingRules.NewPartAndSystemAfterFinalBarline = measures === 0;
      if (selectionKey !== loadedSelection) {
        await osmd.load(filteredScore(selection));
        loadedSelection = selectionKey;
        parses++;
      }
      const parsed = performance.now();
      const key = selectionKey + ':' + measures;
      let scale = scales.get(key);
      if (scale === undefined) {
        scale = 1;
        if (measures) {
          let widths = widthsBySelection.get(selectionKey);
          if (!widths) {
            // One measurement pass replaces repeated whole-score trial layouts.
            layoutOnly(1);
            widths = osmd.graphic.MeasureList.filter(row => row?.[0]).map(row =>
              Math.max(...row.map(m => m.minimumStaffEntriesWidth + m.beginInstructionsWidth + m.endInstructionsWidth))
              + 2 * osmd.EngravingRules.MeasureLeftMargin);
            if (widthsBySelection.size >= 8) widthsBySelection.delete(widthsBySelection.keys().next().value);
            widthsBySelection.set(selectionKey, widths);
          }
          let widest = 0;
          for (let i = 0; i < widths.length; i += measures) {
            widest = Math.max(widest, widths.slice(i, i + measures).reduce((a, b) => a + b, 0));
          }
          const rules = osmd.EngravingRules;
          const margins = rules.PageLeftMargin + rules.PageRightMargin + 10;
          scale = Math.min(1, Math.max(0.2, score.offsetWidth / 10 / (widest + margins)));
        }
      }
      const fitted = performance.now();
      for (let attempt = 0; attempt < 7; attempt++) {
        osmd.Zoom = scale;
        osmd.render();
        fullDraws++;
        if (!measures || fits(measures)) break;
        if (scale <= 0.2 || attempt === 6) throw new Error('Score too dense for this layout');
        scale = Math.max(0.2, scale * 0.85);
      }
      if (scales.size >= 48) scales.delete(scales.keys().next().value);
      scales.set(key, scale);
      if (!score.querySelector('svg')) throw new Error('No pages rendered');
      selected = selection;
      for (const svg of score.querySelectorAll('svg')) svg.parentElement.classList.add('music-page');
      window.scrollTo(0, 0);
      lastTiming = { parseMS: parsed - started, fitMS: fitted - parsed, drawMS: performance.now() - fitted, totalMS: performance.now() - started };
      return this.layoutInfo();
    },
    layoutInfo() {
      return { measuresPerLine: lineCounts(), pages: osmd.graphic.MusicPages.length, notationScale: osmd.Zoom,
        parts, selectedPartIDs: selected, renderedPartCount: osmd.Sheet.Instruments.length, sourceMeasureCount: osmd.Sheet.SourceMeasures.length, timings: lastTiming, fullDraws, parses };
    },
    zoom(value) { score.style.zoom = Math.min(2, Math.max(0.5, value)); }
  };
})();

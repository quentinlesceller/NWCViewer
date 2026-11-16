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
  let pageLayout = { landscape: false, marginMM: 15, noteSize: 100 };
  let navigation = [], suppressPosition = false;
  function geometry(scale) {
    const margin = pageLayout.marginMM * (794 / 210) / scale / 10;
    for (const side of ['Left', 'Right', 'Top', 'Bottom']) osmd.EngravingRules['Page' + side + 'Margin'] = margin;
  }
  function pages() { return [...score.querySelectorAll('.music-page svg')]; }
  function position() {
    const list = pages();
    let index = list.findIndex(svg => svg.getBoundingClientRect().bottom > 40);
    if (index < 0) index = Math.max(0, list.length - 1);
    const rect = list[index]?.getBoundingClientRect();
    return { page: index + 1, offset: rect ? Math.max(0, Math.min(1, -rect.top / rect.height)) : 0 };
  }
  function reportPosition() {
    if (!suppressPosition && pages().length) window.webkit?.messageHandlers?.readingPosition?.postMessage(position());
  }
  let scrollTimer;
  window.addEventListener('scroll', () => { clearTimeout(scrollTimer); scrollTimer = setTimeout(reportPosition, 150); }, { passive: true });
  function lineCounts() {
    return osmd.graphic.MusicPages.flatMap(page => page.MusicSystems.map(system =>
      system.StaffLines[0].Measures.filter(measure => !measure.IsExtraGraphicalMeasure).length));
  }
  function fits(measures) { return lineCounts().slice(0, -1).every(count => count === measures); }
  function layoutOnly(scale) {
    // Same A4 layout calculation as the pinned OSMD render(), without building
    // thousands of SVG nodes for each trial size. Only the final layout is drawn.
    geometry(scale);
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
    async load(xml, measures = 4, ids = null, layout = null) {
      source = new DOMParser().parseFromString(xml, 'application/xml');
      if (source.querySelector('parsererror')) throw new Error('Invalid score XML');
      parts = [...source.querySelectorAll('part-list > score-part')].map(part => ({
        id: part.getAttribute('id'), name: part.querySelector('part-name')?.textContent?.trim() || part.getAttribute('id')
      }));
      loadedSelection = null;
      scales.clear(); widthsBySelection.clear();
      // A file may have been edited since the saved voice selection was recorded.
      if (ids !== null) { ids = ids.filter(id => parts.some(part => part.id === id)); if (!ids.length) ids = null; }
      return this.configure(measures, ids, layout);
    },
    async configure(measures, ids = null, layout = null) {
      const started = performance.now();
      if (!source || !choices.includes(measures)) throw new Error('Invalid layout');
      const requested = ids === null ? parts.map(part => part.id) : ids;
      if (!Array.isArray(requested) || !requested.length || requested.some(id => !parts.some(part => part.id === id))) throw new Error('Invalid voice selection');
      const selection = parts.map(part => part.id).filter(id => requested.includes(id));
      const selectionKey = JSON.stringify(selection);
      if (layout) {
        if (![10, 15, 20, 25].includes(layout.marginMM) || ![75, 100, 125, 150].includes(layout.noteSize)) throw new Error('Invalid page layout');
        pageLayout = { ...layout, landscape: !!layout.landscape };
      }
      score.style.width = (pageLayout.landscape ? 1123 : 794) + 'px';
      osmd.setOptions({ pageFormat: pageLayout.landscape ? 'A4_L' : 'A4_P' });
      osmd.setOptions({ newSystemFromXML: measures === 0, newPageFromXML: measures === 0 });
      osmd.EngravingRules.RenderXMeasuresPerLineAkaSystem = measures;
      osmd.EngravingRules.NewPartAndSystemAfterFinalBarline = measures === 0;
      if (selectionKey !== loadedSelection) {
        await osmd.load(filteredScore(selection));
        loadedSelection = selectionKey;
        parses++;
      }
      const parsed = performance.now();
      const key = selectionKey + ':' + measures + ':' + JSON.stringify(pageLayout);
      let scale = scales.get(key);
      if (scale === undefined) {
        scale = pageLayout.noteSize / 100;
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
          scale = Math.min(pageLayout.noteSize / 100, Math.max(0.2, score.offsetWidth / 10 / (widest + margins)));
        }
      }
      const fitted = performance.now();
      for (let attempt = 0; attempt < 7; attempt++) {
        geometry(scale);
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
      navigation = [];
      osmd.graphic.MusicPages.forEach((page, pageIndex) => {
        for (const system of page.MusicSystems) for (const measure of system.StaffLines[0].Measures) {
          if (measure.IsExtraGraphicalMeasure) continue;
          const sourceMeasure = measure.parentSourceMeasure;
          navigation.push({ number: sourceMeasure.MeasureNumber, page: pageIndex + 1,
            y: system.PositionAndShape.RelativePosition.y * 10 * osmd.Zoom });
        }
      });
      lastTiming = { parseMS: parsed - started, fitMS: fitted - parsed, drawMS: performance.now() - fitted, totalMS: performance.now() - started };
      return this.layoutInfo();
    },
    layoutInfo() {
      return { measuresPerLine: lineCounts(), pages: osmd.graphic.MusicPages.length, notationScale: osmd.Zoom,
        pageWidth: pageLayout.landscape ? 1123 : 794, navigation, measureNumbers: osmd.Sheet.SourceMeasures.map(m => m.MeasureNumber), parts, selectedPartIDs: selected, renderedPartCount: osmd.Sheet.Instruments.length, sourceMeasureCount: osmd.Sheet.SourceMeasures.length, timings: lastTiming, fullDraws, parses };
    },
    position,
    goToPage(page, offset = 0) {
      const svg = pages()[Math.max(0, Math.min(pages().length - 1, page - 1))];
      if (!svg) return false;
      const rect = svg.getBoundingClientRect();
      window.scrollTo(0, Math.max(0, scrollY + rect.top + Math.max(0, Math.min(1, offset)) * rect.height - (offset ? 0 : 16)));
      reportPosition(); return true;
    },
    goToMeasure(number) {
      if (!osmd.Sheet.SourceMeasures.some(m => m.MeasureNumber === number)) return false;
      // A multi-measure rest has one graphical measure for several source bars.
      const target = navigation.find(item => item.number === number) || [...navigation].reverse().find(item => item.number <= number);
      if (!target) return false;
      const rect = pages()[target.page - 1].getBoundingClientRect();
      window.scrollTo(0, Math.max(0, scrollY + rect.top + target.y * Number(score.style.zoom || 1) - 35));
      reportPosition(); return true;
    },
    suspendPosition(value) { suppressPosition = value; },
    zoom(value) {
      const anchor = position();
      score.style.zoom = Math.min(2, Math.max(0.25, value));
      this.goToPage(anchor.page, anchor.offset);
    }
  };
})();

const imageInput = document.getElementById('imageInput');
const analyzeBtn = document.getElementById('analyzeBtn');
const loading = document.getElementById('loading');
const errorBox = document.getElementById('error');

const preview = document.getElementById('preview');
const previewEmpty = document.getElementById('previewEmpty');

const result = document.getElementById('result');
const faultText = document.getElementById('faultText');
const confidenceText = document.getElementById('confidenceText');
const ragCards = document.getElementById('ragCards');
const geminiText = document.getElementById('geminiText');

const captureBtn = document.getElementById('captureBtn');

let currentFile = null;

function formatGeminiResponse(text) {
  // Lightweight, safe Markdown-ish renderer.
  // We keep it small (no external libs) but robust for:
  // - headings (#, ##, ###)
  // - horizontal rules (---)
  // - unordered lists (- item)
  // - ordered lists (1. item)
  // - paragraphs
  // - inline **bold** and *italic*

  const escapeHtml = (s) => {
    const div = document.createElement('div');
    div.textContent = s;
    return div.innerHTML;
  };

  const applyInline = (s) => {
    let out = s;
    out = out.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    out = out.replace(/(^|[^*])\*(?!\s)([^*]+?)\*(?!\*)/g, '$1<em>$2</em>');
    return out;
  };

  const lines = String(text || '').replace(/\r\n/g, '\n').split('\n');

  let html = '';
  let inUl = false;
  let inOl = false;
  let paragraph = '';

  const flushParagraph = () => {
    if (!paragraph) {
      return;
    }

    html += `<p>${applyInline(paragraph)}</p>`;
    paragraph = '';
  };

  const closeLists = () => {
    if (inUl) {
      html += '</ul>';
      inUl = false;
    }
    if (inOl) {
      html += '</ol>';
      inOl = false;
    }
  };

  for (const rawLine of lines) {
    const line = escapeHtml(rawLine);
    const trimmed = line.trim();

    // Blank line => paragraph break
    if (!trimmed) {
      flushParagraph();
      closeLists();
      continue;
    }

    // Horizontal rule
    if (/^---+$/.test(trimmed)) {
      flushParagraph();
      closeLists();
      html += '<hr />';
      continue;
    }

    // Headings
    const h3 = trimmed.match(/^###\s+(.*)$/);
    const h2 = trimmed.match(/^##\s+(.*)$/);
    const h1 = trimmed.match(/^#\s+(.*)$/);
    if (h3 || h2 || h1) {
      flushParagraph();
      closeLists();
      const level = h3 ? 3 : h2 ? 2 : 1;
      const textContent = (h3 || h2 || h1)[1];
      html += `<h${level}>${applyInline(textContent)}</h${level}>`;
      continue;
    }

    // Unordered list
    const ul = trimmed.match(/^-\s+(.*)$/);
    if (ul) {
      flushParagraph();
      if (inOl) {
        html += '</ol>';
        inOl = false;
      }
      if (!inUl) {
        html += '<ul>';
        inUl = true;
      }
      html += `<li>${applyInline(ul[1])}</li>`;
      continue;
    }

    // Ordered list
    const ol = trimmed.match(/^\d+\.\s+(.*)$/);
    if (ol) {
      flushParagraph();
      if (inUl) {
        html += '</ul>';
        inUl = false;
      }
      if (!inOl) {
        html += '<ol>';
        inOl = true;
      }
      html += `<li>${applyInline(ol[1])}</li>`;
      continue;
    }

    // Regular paragraph line
    closeLists();
    paragraph += (paragraph ? ' ' : '') + trimmed;
  }

  flushParagraph();
  closeLists();

  return html;
}

function parseRagContext(raw) {
  const text = String(raw || '').replace(/\r\n/g, '\n');
  const blocks = [];

  // Match headers like: [CONTEXT 1 | source=... | score=0.1234]
  const re = /\[CONTEXT\s+(\d+)\s*\|\s*source=([^\]|]+)\s*\|\s*score=([0-9.]+)\]/gim;

  const matches = [];
  let m;
  while ((m = re.exec(text)) !== null) {
    matches.push({
      index: m.index,
      number: Number(m[1]),
      source: (m[2] || '').trim(),
      score: Number(m[3]),
      headerLen: m[0].length,
    });
  }

  if (!matches.length) return blocks;

  for (let i = 0; i < matches.length; i++) {
    const start = matches[i].index + matches[i].headerLen;
    const end = i + 1 < matches.length ? matches[i + 1].index : text.length;
    const body = text.slice(start, end).trim();
    blocks.push({
      number: matches[i].number,
      source: matches[i].source,
      score: matches[i].score,
      body,
    });
  }
  return blocks;
}

function renderRagCards(container, raw) {
  if (!container) return;
  container.innerHTML = '';

  const rawText = String(raw || '').trim();
  if (!rawText) {
    const empty = document.createElement('div');
    empty.className = 'rag-empty';
    empty.textContent = 'No retrieved context available.';
    container.appendChild(empty);
    return;
  }

  const blocks = parseRagContext(rawText);
  if (!blocks.length) {
    const pre = document.createElement('pre');
    pre.className = 'pre rag-output';
    pre.textContent = rawText;
    container.appendChild(pre);
    return;
  }

  const formatRagBody = (bodyText) => {
    const root = document.createElement('div');
    root.className = 'rag-body';

    const lines = String(bodyText || '').replace(/\r\n/g, '\n').split('\n');
    let ul = null;

    const flushList = () => {
      if (ul) {
        root.appendChild(ul);
        ul = null;
      }
    };

    const addSubtitle = (text) => {
      flushList();
      const el = document.createElement('div');
      el.className = 'rag-subtitle';
      el.textContent = text;
      root.appendChild(el);
    };

    const addKv = (k, v) => {
      flushList();
      const row = document.createElement('div');
      row.className = 'rag-kv';

      const key = document.createElement('div');
      key.className = 'rag-k';
      key.textContent = k;

      const val = document.createElement('div');
      val.className = 'rag-v';
      val.textContent = v;

      row.appendChild(key);
      row.appendChild(val);
      root.appendChild(row);
    };

    const addBullet = (text) => {
      if (!ul) {
        ul = document.createElement('ul');
        ul.className = 'rag-list';
      }
      const li = document.createElement('li');
      li.textContent = text;
      ul.appendChild(li);
    };

    for (const rawLine of lines) {
      const line = String(rawLine || '').trim();
      if (!line) {
        flushList();
        continue;
      }

      // Section-ish headings
      if (/^(SECTION\s+[A-Z0-9]+:|SOP-[A-Z0-9-]+|THRESH-[A-Z0-9-]+|DOC-[A-Z0-9-]+)\b/i.test(line)) {
        addSubtitle(line);
        continue;
      }

      // Numbered titles like "1) Dusty" or "3) Physical-Damage"
      if (/^\d+\)\s+/.test(line)) {
        addSubtitle(line);
        continue;
      }

      // Bullets with key/value
      const kv1 = line.match(/^[-•]\s*([A-Za-z][A-Za-z\s/&-]{1,32}):\s*(.+)$/);
      if (kv1) {
        addKv(kv1[1], kv1[2]);
        continue;
      }

      // Plain key/value lines
      const kv2 = line.match(/^([A-Za-z][A-Za-z\s/&-]{1,32}):\s*(.+)$/);
      if (kv2) {
        addKv(kv2[1], kv2[2]);
        continue;
      }

      // Standard bullet
      const b = line.match(/^[-•]\s+(.+)$/);
      if (b) {
        addBullet(b[1]);
        continue;
      }

      // Fallback: treat as bullet for readability
      addBullet(line);
    }

    flushList();
    return root;
  };

  blocks.forEach((b) => {
    const card = document.createElement('div');
    card.className = 'rag-card';

    const header = document.createElement('div');
    header.className = 'rag-card-header';

    const left = document.createElement('div');
    left.className = 'rag-card-title';
    left.textContent = `Context ${b.number}`;

    const meta = document.createElement('div');
    meta.className = 'rag-card-meta';

    const src = document.createElement('span');
    src.className = 'badge rag-src';
    src.textContent = b.source || 'unknown';

    const score = document.createElement('span');
    score.className = 'badge rag-score';
    score.textContent = Number.isFinite(b.score) ? `score ${b.score.toFixed(4)}` : 'score -';

    meta.appendChild(src);
    meta.appendChild(score);

    header.appendChild(left);
    header.appendChild(meta);

    const body = document.createElement('div');
    body.className = 'rag-card-body';
    body.appendChild(formatRagBody(b.body));

    card.appendChild(header);
    card.appendChild(body);
    container.appendChild(card);
  });
}

function enhanceGeminiMarkup(container) {
  if (!container) return;

  const normalize = (s) => String(s || '').replace(/\s+/g, ' ').trim().toLowerCase();

  const headings = container.querySelectorAll('h2');
  headings.forEach((h) => {
    const t = (h.textContent || '').trim();
    const m = t.match(/^(\d+)\)\s*(.*)$/);
    if (m) {
      const num = m[1];
      const title = m[2];
      h.innerHTML = `<span class="section-num">${num}</span><span class="section-title">${title}</span>`;
    }
  });

  const summaryH2 = Array.from(container.querySelectorAll('h2')).find(
    (h) => normalize(h.textContent) === 'summary'
  );
  if (!summaryH2) return;

  const ul = summaryH2.nextElementSibling;
  if (!ul || ul.tagName !== 'UL') return;

  const rows = [];
  Array.from(ul.querySelectorAll('li')).forEach((li) => {
    const strong = li.querySelector('strong');
    const keyRaw = strong ? strong.textContent : '';
    const key = String(keyRaw || '').replace(/:$/, '').trim();

    let value = li.textContent || '';
    if (keyRaw) value = value.replace(keyRaw, '');
    value = value.replace(/^\s*:\s*/, '').trim();
    rows.push({ key, value });
  });

  const grid = document.createElement('div');
  grid.className = 'summary-grid';

  rows.forEach(({ key, value }) => {
    const k = document.createElement('div');
    k.className = 'summary-k';
    k.textContent = key;

    const v = document.createElement('div');
    v.className = 'summary-v';

    if (normalize(key) === 'urgency') {
      const badge = document.createElement('span');
      const u = normalize(value);
      badge.className = `badge urgency ${u ? `urgency-${u}` : ''}`.trim();
      badge.textContent = value || '-';
      v.appendChild(badge);
    } else {
      v.textContent = value || '-';
    }

    grid.appendChild(k);
    grid.appendChild(v);
  });

  ul.replaceWith(grid);
}

function setError(msg) {
  if (!msg) {
    errorBox.classList.add('hidden');
    errorBox.textContent = '';
    return;
  }
  errorBox.textContent = msg;
  errorBox.classList.remove('hidden');
}

function setLoading(isLoading) {
  loading.classList.toggle('hidden', !isLoading);
  analyzeBtn.disabled = isLoading || !currentFile;
}

imageInput.addEventListener('change', () => {
  const f = imageInput.files && imageInput.files[0];
  currentFile = f || null;
  setError('');
  result.classList.add('hidden');

  if (!currentFile) {
    preview.style.display = 'none';
    previewEmpty.classList.remove('hidden');
    analyzeBtn.disabled = true;
    return;
  }

  const url = URL.createObjectURL(currentFile);
  preview.src = url;
  preview.onload = () => URL.revokeObjectURL(url);
  preview.style.display = 'block';
  previewEmpty.classList.add('hidden');
  analyzeBtn.disabled = false;
});

analyzeBtn.addEventListener('click', async () => {
  if (!currentFile) return;

  setError('');
  setLoading(true);
  result.classList.add('hidden');

  try {
    const form = new FormData();
    form.append('file', currentFile);

    const resp = await fetch('/analyze', {
      method: 'POST',
      body: form,
    });

    const data = await resp.json().catch(() => ({}));

    if (!resp.ok) {
      const detail = data && (data.detail || JSON.stringify(data));
      throw new Error(detail || `Request failed (${resp.status})`);
    }

    faultText.textContent = data.fault ?? '-';
    confidenceText.textContent = (typeof data.confidence === 'number') ? data.confidence.toFixed(4) : '-';
    renderRagCards(ragCards, data.rag_context ?? '');
    
    // Format Gemini output as HTML
    const geminiContent = data.gemini_suggestion ?? '';
    geminiText.innerHTML = formatGeminiResponse(geminiContent);
    enhanceGeminiMarkup(geminiText);

    result.classList.remove('hidden');
  } catch (e) {
    setError(e && e.message ? e.message : String(e));
  } finally {
    setLoading(false);
  }
});

captureBtn.addEventListener("click", async () => {
  alert("Capture button clicked");
  setError('');
  captureBtn.disabled = true;
  captureBtn.innerText = "Capturing…";

  try {
    // 1. Capture & store on backend
    const res = await fetch("/capture-and-store", { method: "POST" });
    if (!res.ok) throw new Error("ESP32 capture failed");

    const data = await res.json();

    // 2. Load image for preview
    const imgUrl = `/captures/${data.filename}?t=${Date.now()}`;
    preview.src = imgUrl;
    preview.style.display = 'block';
    previewEmpty.classList.add('hidden');

    // 3. Fetch image as Blob and convert to File
    const imgResp = await fetch(imgUrl);
    const blob = await imgResp.blob();

    currentFile = new File([blob], data.filename, { type: blob.type });

    // 4. Enable analyze button properly
    analyzeBtn.disabled = false;

    result.classList.add('hidden');

  } catch (err) {
    setError("Failed to capture image from ESP32-CAM");
  } finally {
    captureBtn.disabled = false;
    captureBtn.innerText = "Capture Image (ESP32)";
  }
});


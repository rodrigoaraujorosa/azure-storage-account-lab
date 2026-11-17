// Upload direto ao Blob Storage com SAS, em blocos (Put Block + Put Block List).
// Fluxo: 1) POST {apiBaseUrl}/sas no APIM -> SAS; 2) PUT dos blocos direto no Storage; 3) commit.
"use strict";

const MIB = 1024 * 1024;
const MAX_RETRIES = 3;
const config = window.APP_CONFIG || {};

const $ = (id) => document.getElementById(id);
const fileInput = $("file");
const drop = $("drop");
const button = $("upload");
const bar = $("bar");
const statusEl = $("status");
const statsEl = $("stats");
const logEl = $("log");

let selectedFile = null;

// ---------- UI ----------

function log(message) {
  const item = document.createElement("li");
  item.textContent = `${new Date().toLocaleTimeString()}  ${message}`;
  logEl.append(item);
  logEl.scrollTop = logEl.scrollHeight;
}

function setStatus(text, kind = "") {
  statusEl.textContent = text;
  statusEl.className = kind;
}

function fmtBytes(n) {
  return n >= MIB ? `${(n / MIB).toFixed(1)} MiB` : `${(n / 1024).toFixed(0)} KiB`;
}

function showStats(rows) {
  statsEl.replaceChildren();
  for (const [label, value] of rows) {
    const dt = document.createElement("dt");
    const dd = document.createElement("dd");
    dt.textContent = label;
    dd.textContent = value;
    statsEl.append(dt, dd);
  }
}

function selectFile(file) {
  selectedFile = file || null;
  $("file-label").textContent = file ? `${file.name} · ${fmtBytes(file.size)}` : "Escolha um arquivo";
  button.disabled = !file;
  setStatus(file ? "Pronto para enviar." : "Nenhum arquivo selecionado.");
}

fileInput.addEventListener("change", () => selectFile(fileInput.files[0]));
drop.addEventListener("dragover", (e) => { e.preventDefault(); drop.classList.add("over"); });
drop.addEventListener("dragleave", () => drop.classList.remove("over"));
drop.addEventListener("drop", (e) => {
  e.preventDefault();
  drop.classList.remove("over");
  selectFile(e.dataTransfer.files[0]);
});

// ---------- 1. SAS pelo APIM ----------

async function requestSas(file) {
  if (!config.apiBaseUrl) throw new Error("config.js sem apiBaseUrl (rode scripts/05-frontend.sh)");
  const response = await fetch(`${config.apiBaseUrl}/sas`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      fileName: file.name,
      size: file.size,
      contentType: file.type || "application/octet-stream",
    }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error || `APIM respondeu ${response.status}`);
  return body;
}

// ---------- 2. Blocos direto no Storage ----------

// IDs de bloco: base64 de strings do mesmo tamanho (exigência do serviço).
const blockId = (i) => btoa(`block-${String(i).padStart(6, "0")}`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// XHR em vez de fetch: só o XHR informa o progresso do envio.
function putBlock(sasUrl, id, chunk, onProgress) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("PUT", `${sasUrl}&comp=block&blockid=${encodeURIComponent(id)}`);
    xhr.upload.onprogress = (e) => onProgress(e.loaded);
    xhr.onload = () =>
      xhr.status === 201
        ? resolve()
        : reject(new Error(`Put Block ${xhr.status}: ${xhr.responseText.slice(0, 300)}`));
    xhr.onerror = () => reject(new Error("falha de rede (confira o CORS da conta de upload)"));
    xhr.send(chunk);
  });
}

async function uploadBlocks(sasUrl, file, blockSize, parallel, onProgress) {
  const count = Math.ceil(file.size / blockSize);
  const ids = Array.from({ length: count }, (_, i) => blockId(i));
  const loaded = new Array(count).fill(0);
  const report = () => onProgress(loaded.reduce((a, b) => a + b, 0));
  let next = 0;
  let failed = false;

  async function worker() {
    while (!failed && next < count) {
      const i = next++;
      const chunk = file.slice(i * blockSize, Math.min((i + 1) * blockSize, file.size));
      for (let attempt = 1; ; attempt++) {
        try {
          await putBlock(sasUrl, ids[i], chunk, (n) => { loaded[i] = n; report(); });
          loaded[i] = chunk.size;
          report();
          break;
        } catch (err) {
          loaded[i] = 0;
          report();
          if (attempt >= MAX_RETRIES) { failed = true; throw err; }
          log(`bloco ${i + 1}/${count}: ${err.message} · nova tentativa em ${2 ** attempt}s`);
          await sleep(1000 * 2 ** attempt);
        }
      }
    }
  }

  log(`${count} blocos de ${fmtBytes(blockSize)}, ${parallel} em paralelo`);
  await Promise.all(Array.from({ length: Math.min(parallel, count) }, worker));
  return ids;
}

// ---------- 3. Commit ----------

async function putBlockList(sasUrl, ids, contentType) {
  const xml =
    '<?xml version="1.0" encoding="utf-8"?><BlockList>' +
    ids.map((id) => `<Latest>${id}</Latest>`).join("") +
    "</BlockList>";
  const response = await fetch(`${sasUrl}&comp=blocklist`, {
    method: "PUT",
    headers: { "Content-Type": "application/xml", "x-ms-blob-content-type": contentType },
    body: xml,
  });
  if (response.status !== 201) {
    throw new Error(`Put Block List ${response.status}: ${(await response.text()).slice(0, 300)}`);
  }
}

// ---------- Fluxo ----------

button.addEventListener("click", async () => {
  const file = selectedFile;
  if (!file) return;
  const blockSize = Number($("block-size").value) * MIB;
  const parallel = Number($("parallel").value);
  button.disabled = true;
  bar.style.width = "0";
  logEl.replaceChildren();
  statsEl.replaceChildren();

  try {
    setStatus("Pedindo a SAS ao APIM...");
    const t0 = performance.now();
    const sas = await requestSas(file);
    const sasMs = performance.now() - t0;
    log(`SAS recebida em ${sasMs.toFixed(0)} ms · expira ${new Date(sas.expiresOn).toLocaleTimeString()}`);

    setStatus("Enviando direto ao Storage...");
    const t1 = performance.now();
    const ids = await uploadBlocks(sas.uploadUrl, file, blockSize, parallel, (sent) => {
      const pct = (sent / file.size) * 100;
      bar.style.width = `${pct}%`;
      const secs = (performance.now() - t1) / 1000;
      setStatus(`Enviando... ${pct.toFixed(1)}% · ${(sent / MIB / Math.max(secs, 0.001)).toFixed(1)} MiB/s`);
    });

    setStatus("Confirmando os blocos (Put Block List)...");
    await putBlockList(sas.uploadUrl, ids, file.type || "application/octet-stream");
    const uploadSecs = (performance.now() - t1) / 1000;

    bar.style.width = "100%";
    setStatus("Upload concluído.", "ok");
    log("Put Block List concluído");
    showStats([
      ["Arquivo", `${file.name} (${fmtBytes(file.size)})`],
      ["Blob", sas.blobName],
      ["SAS (APIM)", `${sasMs.toFixed(0)} ms`],
      ["Upload", `${uploadSecs.toFixed(1)} s`],
      ["Vazão", `${(file.size / MIB / uploadSecs).toFixed(1)} MiB/s`],
      ["Blocos", `${ids.length} × ${fmtBytes(blockSize)}, ${parallel} paralelos`],
    ]);
  } catch (err) {
    setStatus(`Erro: ${err.message}`, "err");
    log(`ERRO ${err.message}`);
  } finally {
    button.disabled = !selectedFile;
  }
});

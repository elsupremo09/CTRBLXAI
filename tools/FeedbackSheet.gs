// CTRBLXAI feedback receiver — paste into Google Sheet > Extensions > Apps Script.
// The game POSTs one JSON report per call. The URL must carry ?key=<KEY> (stored in Roblox Secrets).
const KEY = "n5oC-Cwkj_d6UyjaSHHnX0T3k2A9qrS1";
const HEADERS = ["Date (UTC)", "Type", "Message", "Player", "User ID", "Rank", "Screen", "Screens", "Device",
  "Viewport", "Battle", "Place Ver", "Errors", "Report Key", "Fixed", "Notes"];

function safe(v) {
  // Block spreadsheet formula injection from player text.
  const s = v === undefined || v === null ? "" : String(v);
  return /^[=+\-@]/.test(s) ? "'" + s : s;
}

function doPost(e) {
  if (!e || !e.parameter || e.parameter.key !== KEY) {
    return ContentService.createTextOutput("denied");
  }
  const r = JSON.parse(e.postData.contents);
  const book = SpreadsheetApp.getActiveSpreadsheet();
  const tabName = r.dev ? "Studio Tests" : "Feedback";
  let sheet = book.getSheetByName(tabName);
  if (!sheet) {
    sheet = book.insertSheet(tabName);
    sheet.appendRow(HEADERS);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, HEADERS.length).setFontWeight("bold");
  }
  const s = r.server || {}, c = r.client || {};
  sheet.appendRow([
    new Date((s.time || 0) * 1000), safe(r.category), safe(r.text), safe(r.playerName), safe(s.userId),
    safe(s.rank), safe(c.screen), safe((c.screens || []).join(" > ")), safe(c.device), safe(c.viewport),
    s.battleRunning ? "yes" : "no", safe(s.placeVersion), safe((c.errors || []).join(" | ")), safe(r.key), false, ""
  ]);
  sheet.getRange(sheet.getLastRow(), 15).insertCheckboxes();
  return ContentService.createTextOutput("ok");
}

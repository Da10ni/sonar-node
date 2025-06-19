// scripts/push-to-sheets.mjs
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { google } from "googleapis";
import { glob } from "glob"; // ✅ glob v8+ async import

// ✅ __dirname workaround for ES Modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ✅ Load env vars from GitHub Actions or .env (for local testing)
const sheetId = process.env.SHEET_ID;
const credsBase64 = process.env.GOOGLE_SHEETS_CREDENTIALS_BASE64;

(async () => {
  try {
    if (!sheetId || !credsBase64) throw new Error("Missing env vars");

    // ✅ Decode base64 service account credentials
    const credentials = JSON.parse(
      Buffer.from(credsBase64, "base64").toString("utf8")
    );

    const auth = new google.auth.GoogleAuth({
      credentials,
      scopes: ["https://www.googleapis.com/auth/spreadsheets"],
    });

    const sheets = google.sheets({ version: "v4", auth });

    // ✅ Find latest quality metrics file using async glob
    const files = await glob(
      path.resolve(
        __dirname,
        "../quality-data/processed-data/key_metrics_*.txt"
      )
    );

    const latestFile = files.sort().reverse()[0];

    if (!latestFile) {
      console.log("❌ No key_metrics_*.txt file found.");
      process.exit(1);
    }

    // ✅ Parse metrics into [[key, value], ...] rows
    const lines = fs.readFileSync(latestFile, "utf8").trim().split("\n");
    const values = lines.map((line) => {
      const [k, v] = line.split(":").map((x) => x.trim());
      return [k, v];
    });

    // ✅ Tab name: Run-YYYYMMDD_HHMM
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const tabName = `Run-${timestamp.slice(0, 16)}`;

    // ✅ Create a new tab in the spreadsheet
    await sheets.spreadsheets.batchUpdate({
      spreadsheetId: sheetId,
      requestBody: {
        requests: [
          {
            addSheet: {
              properties: {
                title: tabName,
              },
            },
          },
        ],
      },
    });

    // ✅ Push values to the new sheet tab
    await sheets.spreadsheets.values.update({
      spreadsheetId: sheetId,
      range: `${tabName}!A1:B${values.length}`,
      valueInputOption: "RAW",
      requestBody: { values },
    });

    console.log(`✅ Metrics written to sheet tab: ${tabName}`);
  } catch (err) {
    console.error("❌ Error pushing to Google Sheets:", err.message);
    process.exit(1);
  }
})();

// scripts/push-to-sheets.mjs
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { google } from "googleapis";

// ✅ __dirname for ES Modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ✅ Load env vars
const sheetId = process.env.SHEET_ID;
const credsBase64 = process.env.GOOGLE_SHEETS_CREDENTIALS_BASE64;

(async () => {
  try {
    if (!sheetId || !credsBase64) throw new Error("Missing env vars");

    // ✅ Decode credentials
    const credentials = JSON.parse(
      Buffer.from(credsBase64, "base64").toString("utf8")
    );

    const auth = new google.auth.GoogleAuth({
      credentials,
      scopes: ["https://www.googleapis.com/auth/spreadsheets"],
    });

    const sheets = google.sheets({ version: "v4", auth });

    // ✅ Path to metrics.txt
    const metricsPath = path.resolve(
      __dirname,
      "../target/quality-reports/metrics.txt"
    );

    if (!fs.existsSync(metricsPath)) {
      console.error("❌ metrics.txt not found.");
      process.exit(0); // soft fail
    }

    // ✅ Read and parse metrics.txt
    const lines = fs.readFileSync(metricsPath, "utf8").trim().split("\n");
    const values = lines.map((line) => {
      const [k, v] = line.split(":").map((x) => x.trim());
      return [k, v];
    });

    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const tabName = `Run-${timestamp.slice(0, 16)}`;

    // ✅ Create new sheet/tab
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

    // ✅ Push rows to the sheet
    await sheets.spreadsheets.values.update({
      spreadsheetId: sheetId,
      range: `${tabName}!A1:B${values.length}`,
      valueInputOption: "RAW",
      requestBody: { values },
    });

    console.log(`✅ Metrics pushed to Google Sheets tab: ${tabName}`);
  } catch (err) {
    console.error("❌ Error pushing to Google Sheets:", err.message);
    process.exit(1);
  }
})();

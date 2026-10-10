import fs from "node:fs";
import ICAL from "ical.js";

const documents = JSON.parse(fs.readFileSync(0, "utf8"));
process.stdout.write(JSON.stringify(documents.map((document) => {
  try {
    return { data: ICAL.parse(document) };
  } catch (error) {
    return { error: error.message };
  }
})));

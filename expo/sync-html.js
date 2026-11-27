// Copies ../index.html (the same page as Telegram, Android and iPhone) into html.js for the Expo app.
const fs = require("fs");
const path = require("path");
const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
fs.writeFileSync(path.join(__dirname, "html.js"), "module.exports = " + JSON.stringify(html) + ";\n");
console.log("html.js: " + html.length + " chars");

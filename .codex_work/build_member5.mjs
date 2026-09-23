import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { FileBlob, PresentationFile } from "@oai/artifact-tool";

const sourcePath = "/Users/shiying/Downloads/9106-pre.pptx";
const workspaceDir = "/Users/shiying/Desktop/Slime";
const workDir = path.join(workspaceDir, ".codex_work", "member5_build");
const outputPath = path.join(workspaceDir, "output", "9106-pre_member5_completed.pptx");
const skillDir = "/Users/shiying/.codex/plugins/cache/openai-primary-runtime/presentations/26.909.12148/skills/presentations";
const pythonExecutable = "/Users/shiying/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3";

await fs.mkdir(workDir, { recursive: true });
await fs.mkdir(path.dirname(outputPath), { recursive: true });

const presentation = await PresentationFile.importPptx(await FileBlob.load(sourcePath));
const slide = presentation.resolve("sl/fu1gfa1s");
const title = presentation.resolve("sh/5o7it8z2");
title.text.replace("Introduction", "Rationale");

const COLORS = {
  orange: "#ED5E32",
  orangeDark: "#D7651E",
  dark: "#4A2B16",
  body: "#765B49",
  pale: "#FFF5F0",
  paleStrong: "#FDE8DD",
  divider: "#F2C9B7",
  muted: "#9A7864",
};

function addText(name, text, position, style) {
  const shape = slide.shapes.add({
    geometry: "textbox",
    name,
    position,
    fill: "none",
    line: { fill: "none", width: 0 },
  });
  shape.text = text;
  shape.text.style = {
    typeface: "Arial",
    autoFit: "shrinkText",
    wrap: "square",
    insets: { top: 2, right: 4, bottom: 2, left: 4 },
    ...style,
  };
  return shape;
}

function addRect(name, position, fill) {
  return slide.shapes.add({
    geometry: "rect",
    name,
    position,
    fill,
    line: { fill: "none", width: 0 },
  });
}

addText(
  "member5-subtitle",
  "Each design choice responds directly to a passenger need or an operational constraint.",
  { left: 68, top: 200, width: 1227, height: 58 },
  { fontSize: 30, color: COLORS.body, verticalAlignment: "middle" },
);

addText(
  "member5-column-design",
  "DESIGN RESPONSE",
  { left: 83, top: 292, width: 455, height: 40 },
  { fontSize: 22, bold: true, color: COLORS.orangeDark, verticalAlignment: "middle" },
);
addText(
  "member5-column-rationale",
  "WHY IT HELPS",
  { left: 592, top: 292, width: 690, height: 40 },
  { fontSize: 22, bold: true, color: COLORS.orangeDark, verticalAlignment: "middle" },
);

const rows = [
  {
    feature: "Recommended queue window",
    rationale: "Replaces guesswork with a practical time range, reducing early queueing and standing.",
  },
  {
    feature: "WAIT / GET READY / JOIN NOW",
    rationale: "Gives each passenger a clear cue, so decisions rely less on other people’s behaviour.",
  },
  {
    feature: "Automatic updates",
    rationale: "Responds to changing boarding progress and queue conditions, reducing uncertainty.",
  },
  {
    feature: "Proposed automated data",
    rationale: "Combines boarding scans and anonymous queue counts, so gate agents do not assign individual times.",
  },
  {
    feature: "Advisory guidance",
    rationale: "Keeps boarding groups and eligibility unchanged, preserving passenger choice and fairness.",
  },
];

const rowTop = 342;
const rowHeight = 112;
for (let i = 0; i < rows.length; i += 1) {
  const top = rowTop + i * rowHeight;
  addRect(
    `member5-row-${i + 1}-background`,
    { left: 68, top, width: 1227, height: 104 },
    i === rows.length - 1 ? COLORS.paleStrong : i % 2 === 0 ? COLORS.pale : "#FFFFFF",
  );
  addText(
    `member5-row-${i + 1}-number`,
    String(i + 1).padStart(2, "0"),
    { left: 82, top, width: 50, height: 104 },
    { fontSize: 24, bold: true, color: COLORS.orange, alignment: "center", verticalAlignment: "middle" },
  );
  addText(
    `member5-row-${i + 1}-feature`,
    rows[i].feature,
    { left: 145, top, width: 390, height: 104 },
    { fontSize: 27, bold: true, color: COLORS.dark, verticalAlignment: "middle" },
  );
  addRect(
    `member5-row-${i + 1}-divider`,
    { left: 558, top: top + 14, width: 2, height: 76 },
    COLORS.divider,
  );
  addText(
    `member5-row-${i + 1}-rationale`,
    rows[i].rationale,
    { left: 588, top, width: 690, height: 104 },
    { fontSize: 25, color: COLORS.body, verticalAlignment: "middle" },
  );
}

addText(
  "member5-validation-note",
  "These links are design hypotheses to validate through prototyping and user feedback.",
  { left: 68, top: 925, width: 1227, height: 45 },
  { fontSize: 18, italic: true, color: COLORS.muted, verticalAlignment: "middle" },
);

slide.speakerNotes.textFrame.setText(`ENGLISH SCRIPT

The main issue is not a lack of boarding information. It is uncertainty about when joining the physical queue is worthwhile. The recommended queue window turns live conditions into a practical time range, which can reduce unnecessary standing. The three status messages give each passenger a simple personal cue, so they do not need to follow the crowd. Because the recommendation updates with boarding progress and queue conditions, it can respond as the situation changes. The concept also proposes using existing boarding scans and anonymous queue counts, rather than asking gate agents to assign individual times or repeatedly answer the same question. Finally, the guidance remains optional and does not change boarding groups or eligibility. These links explain why the concept fits both the passenger needs and the staff-workload constraint, although they still need to be tested through prototyping.

中文讲稿

这个问题的核心不是缺少登机信息，而是乘客不确定什么时候加入实体队伍才值得。推荐排队时间窗把实时情况转化为一个实用的时间范围，从而减少不必要的站立等待。WAIT、GET READY 和 JOIN NOW 三种状态为每位乘客提供清晰提示，让他们不必根据他人的排队行为做决定。由于建议会根据登机进度和队伍情况自动更新，它能随着现场变化作出调整。方案还计划利用现有登机扫描信息和匿名队伍人数统计，避免要求登机口工作人员逐一安排乘客或反复回答同一个问题。最后，这些提示只是建议，不会改变登机分组或乘客资格，因此保留了乘客的选择权。以上联系说明了这个概念为什么能够同时回应乘客需求和工作人员负担限制，但仍需要通过原型测试来验证。

Source: User-provided Smart Queue Window deck and Member 5 role brief. No external claims added.`);
slide.speakerNotes.setVisible(true);

const preview = await slide.export({ format: "png", scale: 2 });
await fs.writeFile(path.join(workDir, "slide-8-preview.png"), new Uint8Array(await preview.arrayBuffer()));
const layout = await slide.export({ format: "layout" });
await fs.writeFile(path.join(workDir, "slide-8.layout.json"), await layout.text());

const { finalizePresentation } = await import(
  pathToFileURL(path.join(skillDir, "container_tools/artifact_tool_utils.mjs")).href
);
const stagingDir = path.join(workspaceDir, ".codex-finalizer");
await fs.mkdir(stagingDir, { recursive: true });
const candidatePath = path.join(stagingDir, "9106-pre_member5_candidate.pptx");
await (await PresentationFile.exportPptx(presentation)).save(candidatePath);

const result = await finalizePresentation({
  workspaceDir,
  candidatePath,
  finalPath: outputPath,
  pythonExecutable,
  integrityValidatorPath: path.join(skillDir, "container_tools/inspect_presentation_package_integrity.py"),
  layoutValidatorPath: path.join(skillDir, "container_tools/inspect_presentation_layout_geometry.py"),
  layoutArgs: [
    "--expected-slide-size-emu", "13003200,9752000",
    "--validate-bullet-geometry",
    "--validate-heading-fit",
  ],
  explicitTotalSlideCount: 10,
  requiredNativeTableOwnerSlides: [],
  requiredNativeChartOwnerSlides: [],
  fontPolicy: {
    basis: "reference",
    families: ["Arial", "Calibri", "Times New Roman", "Verdana"],
    referencePath: sourcePath,
    referenceSha256: "ee924e345139f81f64fdd67aa988c94b42d49c5eabdbdba09be2f49653b1ef01",
  },
  verifyArtifactToolImport: true,
  receiptPath: path.join(stagingDir, "9106-pre_member5_completed.validation.json"),
});

console.log(JSON.stringify({ outputPath, previewPath: path.join(workDir, "slide-8-preview.png"), result }, null, 2));

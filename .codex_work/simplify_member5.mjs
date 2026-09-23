import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { FileBlob, PresentationFile } from "@oai/artifact-tool";

const sourcePath = "/Users/shiying/Desktop/Slime/output/9106-pre_member5_completed.pptx";
const workspaceDir = "/Users/shiying/Desktop/Slime";
const skillDir = "/Users/shiying/.codex/plugins/cache/openai-primary-runtime/presentations/26.909.12148/skills/presentations";
const pythonExecutable = "/Users/shiying/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3";
const workDir = path.join(workspaceDir, ".codex_work", "member5_simple_build");
const outputPath = path.join(workspaceDir, "output", "9106-pre_member5_simple.pptx");

await fs.mkdir(workDir, { recursive: true });
await fs.mkdir(path.dirname(outputPath), { recursive: true });

const presentation = await PresentationFile.importPptx(await FileBlob.load(sourcePath));
const slide = presentation.resolve("sl/fu1gfa1s");

function replaceText(id, oldText, newText) {
  const shape = presentation.resolve(id);
  shape.text.replace(oldText, newText);
}

replaceText(
  "sh/ilgjit0r",
  "Each design choice responds directly to a passenger need or an operational constraint.",
  "Why the Smart Queue Window can help passengers and gate agents",
);
replaceText(
  "sh/1gr21sza",
  "Replaces guesswork with a practical time range, reducing early queueing and standing.",
  "Passengers know when to join, so they may spend less time standing.",
);
replaceText(
  "sh/by1graxw",
  "WAIT / GET READY / JOIN NOW",
  "Three simple messages",
);
replaceText(
  "sh/lo3yxkfy",
  "Gives each passenger a clear cue, so decisions rely less on other people’s behaviour.",
  "WAIT, GET READY and JOIN NOW make the next step clear.",
);
replaceText(
  "sh/y1cfmpg7",
  "Automatic updates",
  "Live information",
);
replaceText(
  "sh/8ruhszy9",
  "Responds to changing boarding progress and queue conditions, reducing uncertainty.",
  "The suggestion changes with the queue and boarding progress.",
);
replaceText(
  "sh/sz6dorex",
  "Proposed automated data",
  "Automatic guidance",
);
replaceText(
  "sh/e18vq1w3",
  "Combines boarding scans and anonymous queue counts, so gate agents do not assign individual times.",
  "Sensors and boarding information provide guidance without extra work for gate agents.",
);
replaceText(
  "sh/14ze1gve",
  "Advisory guidance",
  "Suggestions only",
);
replaceText(
  "sh/n6hw3qdk",
  "Keeps boarding groups and eligibility unchanged, preserving passenger choice and fairness.",
  "Passengers still follow airline announcements and gate closing times.",
);
replaceText(
  "sh/za1cbqts",
  "These links are design hypotheses to validate through prototyping and user feedback.",
  "These expected benefits still need to be tested.",
);

slide.speakerNotes.textFrame.setText(`ENGLISH SCRIPT

These features help solve our problem in five ways. First, the queue window tells passengers when to join, so they may spend less time standing. Second, WAIT, GET READY and JOIN NOW make the next step clear. Third, the suggestion changes with the queue and boarding progress, so the information stays useful. Fourth, sensors and boarding information update the guidance automatically, so gate agents do not need to manage each passenger. Finally, the messages are only suggestions. Passengers still follow airline announcements and gate closing times.

中文讲稿

这些功能通过五个方面帮助解决我们的问题。第一，排队时间窗告诉乘客什么时候加入队伍，因此他们可以少站一会儿。第二，WAIT、GET READY 和 JOIN NOW 让下一步行动更清楚。第三，建议会根据队伍情况和登机进度变化，因此信息能够保持更新。第四，传感器和登机信息会自动更新建议，所以登机口工作人员不需要逐一管理乘客。最后，这些信息只是建议，乘客仍然需要遵守航空公司广播和登机口关闭时间。

Source: User-provided teammate feature script and Smart Queue Window deck. No external claims added.`);
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
const candidatePath = path.join(stagingDir, "9106-pre_member5_simple_candidate.pptx");
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
    referenceSha256: "fc1ca0d855f92fb01865e9799bc0075ab834c7b6608d9a9e838fdf4d344c00a2",
  },
  verifyArtifactToolImport: true,
  receiptPath: path.join(stagingDir, "9106-pre_member5_simple.validation.json"),
});

console.log(JSON.stringify({ outputPath, previewPath: path.join(workDir, "slide-8-preview.png"), result }, null, 2));

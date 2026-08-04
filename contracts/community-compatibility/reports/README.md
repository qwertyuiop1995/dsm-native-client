# 已审核社区报告 / Reviewed community reports

本目录只保存已完成人工隐私检查的结构化兼容性报告。文件名必须与 `reportId` 一致，例如 `cc-000001.json`；`sourceRef` 使用公开的 `issue-N` 或 `pull-N`。请勿提交日志、截图、HAR、DSM 原始响应或任何真实用户数据。

This directory contains only structured compatibility reports that have completed a manual privacy review. The file name must match `reportId`, for example `cc-000001.json`; use a public `issue-N` or `pull-N` for `sourceRef`. Do not submit logs, screenshots, HAR files, raw DSM responses, or real user data.

示例位于 [`../examples/example-report.json`](../examples/example-report.json)。该虚构示例不会进入生成的兼容矩阵。

See [`../examples/example-report.json`](../examples/example-report.json) for a fictional example. The example is never included in the generated compatibility matrix.

## 维护者候选流程 / Maintainer candidate workflow

维护者只能在完成人工隐私检查后，将 App 导出的 submission JSON 与公开来源关联。辅助命令
只读取本地文件并向标准输出生成待复核差异，不会写入本目录、修改 Git 或访问 GitHub：

```bash
python3 tools/community-compatibility/prepare_candidate.py \
  --submission /path/to/submission.json \
  --source-ref issue-123 \
  --submitted-at 2026-08-04 \
  --confirm-privacy-reviewed \
  --format diff
```

The maintainer must complete a manual privacy review before associating an exported submission
JSON with its public source. The helper reads local files and writes a reviewable diff to standard
output only. It does not write this directory, mutate Git, or access GitHub.

该命令不会解析整段 Issue Markdown、评论或附件，也不会推测套件 ID。需要先把允许字段整理
为 submission 契约；结构化校验不能替代人工隐私审核。通过复核后，维护者再显式应用差异并
运行 `validate.py` 与 `generate.py --check`。

The command deliberately does not parse an entire Issue body, comments, or attachments and never
guesses package IDs. Allowed fields must first be represented by the submission contract. Schema
validation does not replace manual privacy review. After reviewing the diff, apply it explicitly,
then run `validate.py` and `generate.py --check`.

正式报告可由维护者增加 `supersedes` 数组，让新报告显式指向被取代的旧报告。旧报告必须
同时标记为 `reviewStatus: superseded`。校验器会阻止悬空引用、自引用、循环关系、日期倒序
和没有后继的 `superseded` 状态；同日替换、多个有效后继或环境键变化只提示人工复核，
不会自动修改证据结论。该字段仅属于正式报告审核元数据，不进入 App 导出的 submission。

A maintainer may add a `supersedes` array to a formal report so the new report explicitly points
to older reports it replaces. Each target must also use `reviewStatus: superseded`. Validation
blocks dangling references, self-reference, cycles, reversed dates, and superseded reports with no
successor. Same-day replacement, multiple active successors, and environment-key changes remain
manual-review warnings. This field is formal-report metadata and never appears in an app submission.

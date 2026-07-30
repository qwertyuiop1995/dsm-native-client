# 写操作结果示例

本目录保存符合 `mutation-result.schema.json` 的完全合成示例。结果对象只包含稳定状态、
数量、安全错误类别和本地化资源键，不得包含原始响应、路径、名称、账号或请求材料。

`submittedButUnverified` 和 `cancellationRequestedAfterSubmission` 必须要求刷新或查询
最终状态，调用方不得据此自动重放写请求。

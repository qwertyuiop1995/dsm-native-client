import SwiftUI

extension View {
    /// 让页面级内容占满宿主提供的区域，避免空数据分支按固有尺寸被父容器垂直居中。
    ///
    /// 普通空状态使用默认居中；包含标题栏、筛选栏或列表的页面使用 `.topLeading`。
    func fillsAvailableContentArea(alignment: Alignment = .center) -> some View {
        frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: alignment
        )
    }
}

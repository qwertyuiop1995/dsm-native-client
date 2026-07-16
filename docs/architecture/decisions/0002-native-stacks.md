# ADR-0002：使用平台原生技术栈

状态：已接受
日期：2026-07-16

## 决策

- Apple：Swift、SwiftUI、URLSession。
- Android：Kotlin、Jetpack Compose、OkHttp。
- Windows：C#、WinUI 3、HttpClient。

## 原因

需要原生文件选择器、安全存储、后台传输、窗口和设备形态体验，不使用跨平台 UI 运行时。

## Apple 代码共享

macOS 使用独立 App，iPhone/iPad 使用通用移动 App；三者共享 Swift Package。这属于 Apple 原生代码复用，不引入跨平台框架。

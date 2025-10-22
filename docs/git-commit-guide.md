# 代码提交规范

本项目采用Angular 规范 ，在 Angular 规范中，Commit Message 包含三个部分，分别是 **Header**、**Body** 和 **Footer**，格式如下：

```
<type>[optional scope]: <description>
// 空行
[optional body]
// 空行
[optional footer(s)]
```
其中，Header是必需的，Body和Footer可以省略。

## Header
Header 部分只有一行，用于存放本次提交更改的简短说明，包括三个字段：type（必选）、scope（可选）和 subject（必选）。
### type
|分类|类型|说明|
|-- |-- | -- |
|代码类|feat|新增功能|
|代码类|fix|修复bug|
|代码类|perf|优化代码行相关|
|代码类|style|代码格式化、缺陷修复等不影响代码含义的修改|
|优化代码类|refactor|重构代码，既不是新增功能也不是修复bug|
|非代码类|test|增加测试用例或更新现有测试|
|非代码类|ci|CI流程相关的修改|
|非代码类|docs|文档更新|
|其他变更|chore|构建过程或辅助工具的变动，如依赖管理、构建脚本、文档生成等|

### scope
scope 用于说明本次提交的影响范围，比如修改了哪个模块、文件、功能等。

### subject
subject 是本次提交的简短描述，不超过50个字符。

## Body
Body 部分是对本次提交的详细描述，可以分为多行，用于提供更详细的信息。

## Footer
Footer 部分可以有多个，用于记录与提交相关的说明，如关闭的 issue、相关的 pull request 等。

## 示例
```
feat(module): add a new feature

 - add a new feature to module
 - update the test case
 - fix the bug

Closes #123
```

## 注意事项 
建议：
- 请勿在 commit message 中使用中文，尽量使用英文。 
- 尽量使用 `git commit` 或者 `git commit -a` 提交代码，这样可以在commit中填写符合 Angular 规范的 commit message。
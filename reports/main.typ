#import "@preview/ilm:1.2.1": *

#set text(lang: "zh")
#show: ilm.with(
  title: [操作系统课程设计\ 实验报告],
  author: "段子涛",
  date: datetime(year: 2024, month: 08, day: 21),
  date-format: "[year]年[month]月[day]日",
  abstract: [2021 版 xv6 及 Labs 课程项目实验，\ 代码放在 #link("https://github.com/meoowny/xv6-labs-tj-os")[https://github.com/meoowny/xv6-labs-tj-os] 仓库下],
  preface: [],
  // figure-index: (enabled: true),
  // table-index: (enabled: true),
  // listing-index: (enabled: true),
  // external-link-circle: false
)

#set text(
  size: 12pt,
  font: ("STIX Two Text", "Source Han Serif SC"),
  lang: "zh",
)
#show raw: set text(font: ("FiraCode NF", "Source Han Sans SC"))
#show heading: it => {
  it
  v(-0.6em)
  box()
}
#show figure: it => {
  it
  v(-1em)
  box()
}
#show heading.where(level: 1): set heading(numbering: "第一章")
#set enum(numbering: "1.A.a)", full: true)
#set par(justify: true, first-line-indent: 2em, leading: 1em)

#pagebreak(to: "odd")
#counter(page).update(1)

// #include "./style-ref.typ"

#include "./chapters/tools.typ"

#include "./chapters/util.typ"    // 1
#include "./chapters/syscall.typ" // 2
#include "./chapters/pgtbl.typ"   // 3
#include "./chapters/traps.typ"   // 4
#include "./chapters/cow.typ"     // 5
#include "./chapters/thread.typ"  // 6
#include "./chapters/net.typ"     // 7
#include "./chapters/lock.typ"    // 8
#include "./chapters/fs.typ"      // 9
#include "./chapters/mmap.typ"    // 10

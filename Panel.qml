import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "alex.ci"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var engine: null

  property string selectedKey: ""
  property string copyNote: ""

  readonly property var runs: engine && engine.runs ? engine.runs : []
  readonly property string selectedLog: engine && engine.logKey === selectedKey ? engine.logText : ""
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string iconFont: "JetBrainsMono Nerd Font"
  readonly property color ink: barForeground
  readonly property color fail: bar ? bar.urgent : Color.urgent

  readonly property var currentRun: {
    for (var i = 0; i < runs.length; i++) {
      if (runKey(runs[i]) === selectedKey) return runs[i]
    }
    return null
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function runKey(run) {
    return String(run.repo) + "#" + String(run.id)
  }

  function repoName(run) {
    var slug = String(run && run.repo ? run.repo : "")
    var slash = slug.indexOf("/")
    return slash >= 0 ? slug.slice(slash + 1) : slug
  }

  function isLive(run) {
    var state = String(run.conclusion || run.status || "")
    return state === "in_progress" || state === "queued" || state === "waiting"
  }

  function isFail(run) {
    var state = String(run.conclusion || run.status || "")
    return state === "failure" || state === "timed_out" || state === "startup_failure"
  }

  function pick(run) {
    root.selectedKey = runKey(run)
    root.copyNote = ""
    if (engine) engine.loadLog(run.repo, run.id)
  }

  function stateLabel(run) {
    if (isFail(run)) return "falhou"
    if (isLive(run)) return "rodando"
    var state = String(run.conclusion || run.status || "")
    if (state === "success") return "ok"
    if (state === "cancelled") return "cancelada"
    return state || "—"
  }

  function stateColor(run) {
    if (isFail(run)) return fail
    if (isLive(run)) return Color.accent
    return ink
  }

  component RunBar: Item {
    id: track
    property bool active: false
    implicitHeight: 2
    height: 2

    Rectangle {
      anchors.fill: parent
      radius: 1
      color: Color.accent
      opacity: 0.22
    }

    Rectangle {
      width: Math.max(28, parent.width * 0.34)
      height: parent.height
      radius: 1
      color: Color.accent
      x: phase * Math.max(0, parent.width - width)

      property real phase: 0
      SequentialAnimation on phase {
        running: track.active && track.visible
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 1100; easing.type: Easing.InOutCubic }
        NumberAnimation { from: 1; to: 0; duration: 1100; easing.type: Easing.InOutCubic }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(368))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(520)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.lg

        Item {
          id: header
          width: parent.width
          height: Math.max(mark.implicitHeight, titles.implicitHeight, refreshHit.height)

          Text {
            id: mark
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f09b}"
            color: root.ink
            font.family: root.iconFont
            font.pixelSize: Style.font.iconLarge
            renderType: Text.NativeRendering
          }

          Column {
            id: titles
            anchors.left: mark.right
            anchors.right: refreshHit.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.lg
            anchors.rightMargin: Style.spacing.lg
            spacing: 0

            Text {
              width: parent.width
              text: "devaction-labs"
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: engine && engine.checkedAt ? engine.checkedAt : (engine && engine.polling ? "atualizando…" : "Actions")
              color: root.ink
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Item {
            id: refreshHit
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.spacing.huge
            height: Style.spacing.huge

            Text {
              id: refreshMark
              anchors.centerIn: parent
              text: "\u{f021}"
              color: engine && engine.polling ? Color.accent : root.ink
              opacity: engine && engine.polling ? 1 : 0.65
              font.family: root.iconFont
              font.pixelSize: Style.font.icon

              RotationAnimation {
                id: refreshSpin
                target: refreshMark
                property: "rotation"
                running: !!(engine && engine.polling)
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 800
                onRunningChanged: if (!running) refreshMark.rotation = 0
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (engine) engine.refresh()
            }
          }
        }

        Text {
          width: parent.width
          visible: engine && engine.errorText !== ""
          text: engine ? engine.errorText : ""
          wrapMode: Text.WordWrap
          color: root.fail
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Flickable {
          id: listFlick
          width: parent.width
          visible: root.runs.length > 0
          height: visible ? Math.min(runColumn.implicitHeight, Style.space(240)) : 0
          contentHeight: runColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: runColumn
            width: listFlick.width
            spacing: Style.spacing.md

            Repeater {
              model: root.runs

              delegate: Rectangle {
                id: card
                required property var modelData
                readonly property bool chosen: root.selectedKey === root.runKey(modelData)
                readonly property bool live: root.isLive(modelData)
                readonly property bool loud: root.isFail(modelData) || live
                readonly property color tone: root.stateColor(modelData)

                width: runColumn.width
                radius: Style.spacing.sm
                color: chosen ? Util.alpha(tone, 0.14) : Util.alpha(root.ink, loud ? 0.05 : 0.03)
                implicitHeight: cardBody.implicitHeight + Style.spacing.md * 2
                height: implicitHeight

                Rectangle {
                  width: 2
                  radius: 1
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.topMargin: Style.spacing.sm
                  anchors.bottomMargin: Style.spacing.sm
                  color: card.tone
                  opacity: card.loud ? 1 : 0.28
                }

                Column {
                  id: cardBody
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.leftMargin: Style.spacing.xl
                  anchors.rightMargin: Style.spacing.md
                  anchors.topMargin: Style.spacing.md
                  spacing: Style.spacing.xxs

                  Item {
                    width: parent.width
                    height: Math.max(repoLabel.implicitHeight, pill.height)

                    Text {
                      id: repoLabel
                      anchors.left: parent.left
                      anchors.right: pill.left
                      anchors.rightMargin: Style.spacing.md
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.repoName(modelData)
                      color: root.ink
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Rectangle {
                      id: pill
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      width: pillLabel.implicitWidth + Style.spacing.md * 2
                      height: pillLabel.implicitHeight + Style.spacing.xs * 2
                      radius: height / 2
                      color: card.loud ? Util.alpha(card.tone, 0.16) : "transparent"

                      Text {
                        id: pillLabel
                        anchors.centerIn: parent
                        text: root.stateLabel(modelData)
                        color: card.tone
                        opacity: card.loud ? 1 : 0.55
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    text: modelData.name + (modelData.branch ? ("  ·  " + modelData.branch) : "")
                    color: root.ink
                    opacity: 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  RunBar {
                    width: parent.width
                    visible: card.live
                    active: card.live && root.opened
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.pick(modelData)
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.runs.length === 0
          text: engine && engine.polling ? "Atualizando…" : "Nenhuma run ativa ou com erro."
          color: root.ink
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Rectangle {
          width: parent.width
          radius: Style.spacing.sm
          color: Util.alpha(root.ink, 0.04)
          implicitHeight: logColumn.implicitHeight + Style.spacing.lg * 2
          height: implicitHeight

          Column {
            id: logColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.spacing.lg
            spacing: Style.spacing.md

            Item {
              width: parent.width
              height: Math.max(logTitle.implicitHeight, copyLabel.implicitHeight)

              Text {
                id: logTitle
                anchors.left: parent.left
                anchors.right: copyLabel.left
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: root.currentRun
                  ? (root.repoName(root.currentRun) + "  ·  " + root.currentRun.name)
                  : "Log"
                color: root.ink
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Text {
                id: copyLabel
                anchors.right: openLabel.left
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                text: root.copyNote !== "" ? root.copyNote : "copiar erro"
                color: Color.accent
                opacity: root.selectedLog === "" ? 0.35 : 1
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.spacing.sm
                  enabled: root.selectedLog !== ""
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (engine && engine.copyLog() === "ok") root.copyNote = "copiado"
                  }
                }
              }

              Text {
                id: openLabel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "abrir"
                color: Color.accent
                opacity: root.currentRun ? 1 : 0.35
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.spacing.sm
                  enabled: !!root.currentRun
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (root.currentRun && engine) engine.openUrl(root.currentRun.url)
                  }
                }
              }
            }

            Flickable {
              id: logFlick
              width: parent.width
              height: Style.space(124)
              contentWidth: width
              contentHeight: logText.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Text {
                id: logText
                width: logFlick.width
                text: engine && engine.logBusy
                  ? "Baixando o log…"
                  : (engine && engine.logError !== ""
                    ? engine.logError
                    : (root.selectedLog !== "" ? root.selectedLog : "Escolhe uma run para ver o erro."))
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: root.ink
                opacity: root.selectedLog === "" && !(engine && engine.logBusy) ? 0.45 : 0.92
                font.family: "monospace"
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }

  Timer {
    interval: 1600
    running: root.copyNote !== ""
    onTriggered: root.copyNote = ""
  }
}

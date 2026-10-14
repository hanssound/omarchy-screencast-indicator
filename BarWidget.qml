import QtQuick
import qs.Commons
import qs.Ui as Ui
import "Model.js" as Model

// macOS-style capture indicator: a purple dot while anything captures the
// screen, faded for a while after it ends. Click for what captured it.
Ui.BarWidget {
  id: root

  readonly property color purple: "#a259ff"
  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(root.moduleName) : null
  readonly property bool capturing: service ? service.active : false
  readonly property bool recent: service ? service.lingering : false
  readonly property var history: service ? service.history : []
  // Setting (shell.json, on the layout entry): linger seconds, default 15.
  readonly property int linger: Math.max(0, Number(setting("linger", 15)) || 0)
  onLingerChanged: if (service) service.lingerSeconds = linger
  onServiceChanged: if (service) service.lingerSeconds = linger

  property bool popupOpen: false
  function close() { popupOpen = false }
  // Ticks only while the popup shows a running capture's duration.
  property real now: Date.now()
  Timer { interval: 1000; repeat: true; running: root.popupOpen && root.capturing; onTriggered: root.now = Date.now() }
  onPopupOpenChanged: now = Date.now()

  readonly property bool shown: capturing || recent || popupOpen
  visible: shown
  implicitWidth: shown ? button.implicitWidth : 0
  implicitHeight: shown ? button.implicitHeight : 0

  Ui.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "●"
    foreground: root.purple
    opacity: root.capturing ? 1 : 0.5
    fontSize: Style.font.caption
    horizontalMargin: 5
    useActiveColor: false
    tooltipText: root.popupOpen || root.history.length === 0 ? ""
      : (root.capturing ? "Capturing: " : "Captured: ") + Model.appsLabel(root.history[root.history.length - 1])
    onPressed: function() { root.popupOpen = !root.popupOpen }
  }

  function clock(ms) {
    return new Date(ms).toLocaleTimeString(Qt.locale(I18n.formatLocale), "HH:mm:ss")
  }

  Ui.PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      width: parent.width
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: root.capturing ? "Screen is being captured" : "Recent screen captures"
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Repeater {
        model: root.popupOpen || popup.visible ? root.history.slice().reverse() : []
        delegate: Column {
          required property var modelData
          width: column.width
          spacing: Style.space(2)

          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: (modelData.end ? "" : "● ") + Model.appsLabel(modelData)
            color: modelData.end ? (root.bar ? root.bar.foreground : Color.foreground) : root.purple
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.clock(modelData.start) + "  ·  " + Model.duration(modelData, root.now) + "  ·  " + modelData.target
            color: root.bar ? root.bar.foreground : Color.foreground
            opacity: 0.6
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      Text {
        visible: root.history.length === 0
        textFormat: Text.PlainText
        text: "No captures since the shell started"
        color: root.bar ? root.bar.foreground : Color.foreground
        opacity: 0.6
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}

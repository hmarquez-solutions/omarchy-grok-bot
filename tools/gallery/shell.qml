import QtQuick
import Quickshell
import qs.Commons

// Dev gallery: every Face mood at bar, hero and poster size.
//   tools/gallery/run
ShellRoot {
  FloatingWindow {
    id: win
    title: "grok-bot-face-gallery"
    implicitWidth: 720
    implicitHeight: 320
    color: Color.background

    readonly property var moods: ["asleep", "idle", "working", "unread", "waiting"]
    readonly property var sizes: [16, 40, 96]

    Column {
      anchors.centerIn: parent
      spacing: 18

      Repeater {
        model: win.sizes

        Row {
          id: sizeRow
          required property int modelData
          spacing: 48

          Repeater {
            model: win.moods

            Item {
              id: cell
              required property string modelData
              width: 96
              height: sizeRow.modelData

              Face {
                anchors.centerIn: parent
                iconSize: sizeRow.modelData
                mood: cell.modelData
                color: cell.modelData === "waiting" ? Color.urgent
                  : cell.modelData === "asleep" ? Qt.darker(Color.foreground, 1.55)
                  : Color.foreground
                eyeColor: Color.background
                nudgeIntervalMs: 3000
              }
            }
          }
        }
      }

      Row {
        spacing: 48
        Repeater {
          model: win.moods
          Text {
            required property string modelData
            width: 96
            text: modelData
            color: Color.foreground
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 12
          }
        }
      }
    }
  }
}

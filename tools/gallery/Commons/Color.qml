pragma Singleton
import QtQuick
QtObject {
  property color foreground: "#cacccc"
  property color background: "#101315"
  property color urgent: "#e0a05a"
  readonly property QtObject bar: QtObject { property color background: "#101315" }
}

import QtQuick 2.15
import QtQuick.Controls 2.15

// SDDM provides config, userModel, sessionModel and sddm as context properties.
Rectangle {
    id: root
    color: config.bgColor
    Image {
        anchors.fill: parent
        source: "Backgrounds/wallpaper.jpg"
        fillMode: Image.PreserveAspectCrop
        opacity: 0.25
    }
    Column {
        anchors.centerIn: parent
        spacing: 16
        width: Math.min(parent.width * 0.8, 420)
        Text {
            text: "Voluta"
            color: config.accentColor
            font.pixelSize: 48
            font.family: "Cinzel"
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text { text: "Sign in"; color: config.fgColor; font.pixelSize: 20 }
        TextField {
            id: username
            width: parent.width
            placeholderText: "Username"
            text: userModel.lastUser
            color: config.fgColor
            placeholderTextColor: config.fgColor
            selectionColor: config.accentColor
            selectedTextColor: config.bgColor
            background: Rectangle { color: config.bgColor; border.color: config.accentColor }
        }
        TextField {
            id: password
            width: parent.width
            placeholderText: "Password"
            echoMode: TextInput.Password
            color: config.fgColor
            placeholderTextColor: config.fgColor
            selectionColor: config.accentColor
            selectedTextColor: config.bgColor
            focus: true
            onAccepted: login.clicked()
            background: Rectangle { color: config.bgColor; border.color: config.accentColor }
        }
        ComboBox {
            id: sessions
            width: parent.width
            model: sessionModel
            textRole: "name"
            currentIndex: sessionModel.lastIndex
            contentItem: Text {
                text: sessions.displayText
                color: config.fgColor
                verticalAlignment: Text.AlignVCenter
            }
            indicator: Text { text: "▾"; color: config.accentColor; anchors.right: parent.right }
            background: Rectangle { color: config.bgColor; border.color: config.accentColor }
            delegate: ItemDelegate {
                id: sessionDelegate
                required property string name
                required property int index
                onClicked: { sessions.currentIndex = index; sessions.popup.close() }
                width: sessions.width
                contentItem: Text { text: sessionDelegate.name; color: config.fgColor }
                background: Rectangle { color: config.bgColor }
            }
            popup: Popup {
                y: sessions.height
                width: sessions.width
                contentItem: ListView { implicitHeight: contentHeight; model: sessions.delegateModel }
                background: Rectangle { color: config.bgColor; border.color: config.accentColor }
            }
        }
        Button {
            id: login
            width: parent.width
            onClicked: sddm.login(username.text, password.text, sessions.currentIndex)
            contentItem: Text {
                text: "Enter"
                color: config.bgColor
                horizontalAlignment: Text.AlignHCenter
            }
            background: Rectangle { color: config.accentColor }
        }
        Text { id: message; text: ""; color: config.fgColor; wrapMode: Text.WordWrap; width: parent.width }
    }
    Connections {
        target: sddm
        function onLoginFailed() {
            message.text = "Sign-in failed. Please try again."
            password.text = ""
            password.forceActiveFocus()
        }
    }
}

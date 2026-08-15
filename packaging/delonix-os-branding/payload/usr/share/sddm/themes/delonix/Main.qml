// DelonixOS — tema de login SDDM
//
// Deliberadamente simples: fundo Delonix, marca com anéis de sinal, campo de
// utilizador e password, selector de sessão e acções de energia.

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
// `sddm`, `userModel` e `sessionModel` são injectados pelo greeter — não há
// import para eles (e SddmComponents é evitado de propósito: partiu entre
// versões e não precisamos de nada de lá).

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#0d0f12"

    readonly property color delonixRed: "#e0202f"
    readonly property color fg:         "#e6e8ec"
    readonly property color muted:      "#8b9099"
    readonly property color surface:    "#16191e"
    readonly property color border:     "#262a31"

    property bool busy: false

    Image {
        anchors.fill: parent
        source: "background.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }

    // ---- cartão de login ---------------------------------------------------
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 420
        height: column.implicitHeight + 64
        radius: 14
        color: Qt.rgba(0.086, 0.098, 0.118, 0.92)
        border.color: root.border
        border.width: 1

        ColumnLayout {
            id: column
            anchors.centerIn: parent
            width: parent.width - 64
            spacing: 18

            // Marca com os mesmos anéis de sinal do splash de arranque.
            Item {
                id: markArea
                width: 132
                height: 132
                Layout.alignment: Qt.AlignHCenter

                Repeater {
                    model: 2
                    delegate: Rectangle {
                        id: wave
                        anchors.centerIn: parent
                        width: 92
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.color: root.delonixRed
                        border.width: 1
                        opacity: 0

                        SequentialAnimation {
                            running: true
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 1100 }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: wave; property: "width"
                                    from: 92; to: 132; duration: 2200
                                    easing.type: Easing.OutCubic
                                }
                                SequentialAnimation {
                                    NumberAnimation { target: wave; property: "opacity"; from: 0; to: 0.45; duration: 500 }
                                    NumberAnimation { target: wave; property: "opacity"; to: 0; duration: 1700 }
                                }
                            }
                        }
                    }
                }

                Image {
                    anchors.centerIn: parent
                    source: "logo.png"
                    sourceSize.width: 88
                    sourceSize.height: 88
                }
            }

            Text {
                text: "DelonixOS"
                color: root.fg
                font.pixelSize: 30
                font.bold: true
                font.letterSpacing: 0.5
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "DevOps · SRE · Platform Engineering"
                color: root.delonixRed
                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 1.2
                Layout.alignment: Qt.AlignHCenter
            }

            // Linha de acento: dá peso à marca sem acrescentar ruído.
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
                Layout.bottomMargin: 8
                width: 64
                height: 2
                radius: 1
                color: root.delonixRed
            }

            // ---- utilizador ----
            ComboBox {
                id: userBox
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                model: userModel
                textRole: "name"
                currentIndex: userModel.lastIndex
                editable: false
                font.pixelSize: 14
                // Sem isto o combo herda o estilo claro do sistema e fica
                // ilegível sobre o cartão escuro.
                contentItem: Text {
                    text: userBox.displayText
                    color: root.fg
                    font: userBox.font
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 12
                    elide: Text.ElideRight
                }
                background: Rectangle {
                    radius: 8
                    color: root.surface
                    border.width: 1
                    border.color: userBox.activeFocus ? root.delonixRed : root.border
                }
            }

            // ---- password ----
            TextField {
                id: passwordField
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                echoMode: TextInput.Password
                placeholderText: "Palavra-passe"
                placeholderTextColor: root.muted
                font.pixelSize: 14
                leftPadding: 12
                focus: true
                color: root.fg
                background: Rectangle {
                    radius: 8
                    color: root.surface
                    border.width: 1
                    border.color: passwordField.activeFocus ? root.delonixRed : root.border
                }
                onAccepted: root.doLogin()
            }

            // ---- mensagem de erro ----
            Text {
                id: errorText
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                color: root.delonixRed
                font.pixelSize: 12
                text: ""
                visible: text !== ""
                wrapMode: Text.WordWrap
            }

            // ---- entrar ----
            Button {
                Layout.fillWidth: true
                text: "Entrar"
                enabled: !root.busy
                onClicked: root.doLogin()
                contentItem: Text {
                    text: parent.text
                    color: "#ffffff"
                    font.pixelSize: 14
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 8
                    implicitHeight: 46
                    color: parent.down ? "#8a0f18" : (parent.hovered ? "#be1622" : root.delonixRed)
                    // Um halo ténue quando tem o foco: dá a saber que o Enter
                    // faz login sem acrescentar mais texto ao ecrã.
                    border.width: parent.activeFocus ? 2 : 0
                    border.color: "#ffffff"
                }
            }

            // ---- sessão ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "Sessão"
                    color: root.muted
                    font.pixelSize: 12
                }
                ComboBox {
                    id: sessionBox
                    Layout.fillWidth: true
                    model: sessionModel
                    textRole: "name"
                    currentIndex: sessionModel.lastIndex
                    font.pixelSize: 12
                }
            }
        }
    }

    function doLogin() {
        if (root.busy) return
        root.busy = true
        errorText.text = ""
        sddm.login(userBox.currentText, passwordField.text, sessionBox.currentIndex)
    }

    // ---- barra de acções ---------------------------------------------------
    RowLayout {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        spacing: 12

        Repeater {
            model: [
                { label: "Suspender", action: "suspend", enabled: sddm.canSuspend },
                { label: "Reiniciar", action: "reboot",  enabled: sddm.canReboot  },
                { label: "Desligar",  action: "power",   enabled: sddm.canPowerOff }
            ]
            delegate: Button {
                text: modelData.label
                enabled: modelData.enabled
                flat: true
                contentItem: Text {
                    text: parent.text
                    color: parent.hovered ? root.fg : root.muted
                    font.pixelSize: 12
                }
                background: Item {}
                onClicked: {
                    if (modelData.action === "suspend") sddm.suspend()
                    else if (modelData.action === "reboot") sddm.reboot()
                    else sddm.powerOff()
                }
            }
        }
    }

    // ---- máquina -------------------------------------------------------------
    // Quem administra várias máquinas agradece saber em qual está ANTES de entrar.
    Text {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 24
        color: root.muted
        font.pixelSize: 13
        text: sddm.hostName
    }

    // ---- relógio -----------------------------------------------------------
    Text {
        id: clock
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 24
        color: root.muted
        font.pixelSize: 13
        text: Qt.formatDateTime(new Date(), "dddd, d MMMM yyyy — HH:mm")
        Timer {
            interval: 10000
            running: true
            repeat: true
            onTriggered: clock.text = Qt.formatDateTime(new Date(), "dddd, d MMMM yyyy — HH:mm")
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            errorText.text = "Credenciais inválidas."
            passwordField.text = ""
            passwordField.forceActiveFocus()
        }
        function onLoginSucceeded() {
            root.busy = false
        }
    }

    Component.onCompleted: passwordField.forceActiveFocus()
}

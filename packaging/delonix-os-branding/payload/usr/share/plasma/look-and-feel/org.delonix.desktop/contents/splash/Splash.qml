// DelonixOS — KSplash (o ecrã entre o login e o desktop).
//
// Continua o splash do Plymouth: mesmo fundo, mesma marca, e os mesmos anéis
// de sinal a propagar-se. Aqui são desenhados em QML (ficam nítidos em
// qualquer DPI) em vez de frames PNG.

import QtQuick 2.15

Image {
    id: root
    source: "images/background.png"
    fillMode: Image.PreserveAspectCrop
    asynchronous: false

    property int stage

    onStageChanged: {
        // A largura da barra vem do binding lá em baixo; aqui só as animações.
        if (stage === 1) introAnimation.running = true
        if (stage === 6) outroAnimation.running = true
    }

    Column {
        anchors.centerIn: parent
        spacing: 24

        // --- marca com anéis a expandir -------------------------------------
        Item {
            id: markArea
            width: 260
            height: 260
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: 0

            Repeater {
                model: 3
                delegate: Rectangle {
                    id: wave
                    anchors.centerIn: parent
                    width: 150
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.color: "#e0202f"
                    border.width: 2
                    opacity: 0

                    SequentialAnimation {
                        running: markArea.opacity > 0
                        loops: Animation.Infinite
                        PauseAnimation { duration: index * 700 }
                        ParallelAnimation {
                            NumberAnimation {
                                target: wave; property: "width"
                                from: 150; to: 260; duration: 2100
                                easing.type: Easing.OutCubic
                            }
                            SequentialAnimation {
                                NumberAnimation {
                                    target: wave; property: "opacity"
                                    from: 0; to: 0.55; duration: 500
                                }
                                NumberAnimation {
                                    target: wave; property: "opacity"
                                    to: 0; duration: 1600
                                }
                            }
                        }
                    }
                }
            }

            Image {
                id: logo
                anchors.centerIn: parent
                source: "images/logo.png"
                sourceSize.width: 180
                sourceSize.height: 180
            }
        }

        Text {
            text: "DelonixOS"
            color: "#e6e8ec"
            font.pixelSize: 26
            font.bold: true
            opacity: markArea.opacity
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: "DevOps · SRE · Platform Engineering"
            color: "#8b9099"
            font.pixelSize: 12
            opacity: markArea.opacity * 0.9
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Rectangle {
            id: progressTrack
            width: 260
            height: 3
            radius: 2
            color: "#ffffff"
            opacity: 0.15
            anchors.horizontalCenter: parent.horizontalCenter

            Rectangle {
                id: progress
                height: parent.height
                radius: parent.radius
                width: progressTrack.width * Math.min(root.stage / 6, 1)
                color: "#e0202f"
                Behavior on width {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    NumberAnimation {
        id: introAnimation
        running: false
        target: markArea
        property: "opacity"
        to: 1
        duration: 400
        easing.type: Easing.OutQuad
    }

    NumberAnimation {
        id: outroAnimation
        running: false
        target: root
        property: "opacity"
        to: 0
        duration: 300
        easing.type: Easing.InQuad
    }
}

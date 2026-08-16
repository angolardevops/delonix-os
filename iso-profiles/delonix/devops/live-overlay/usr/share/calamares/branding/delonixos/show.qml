/* Apresentação durante a instalação.
 *
 * Deliberadamente sóbria: quem instala isto quer ver o progresso, não uma
 * campanha. Três ecrãs com o que a distro traz, e nada a piscar. */
import QtQuick 2.5
import calamares.slideshow 1.0

Presentation {
    id: presentation

    function onActivate()   { presentation.currentSlide = 0 }
    function onLeave()      { }

    Timer {
        interval: 12000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Text {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            color: "#e6e8ec"
            font.pixelSize: 22
            text: "DelonixOS\n\n" +
                  "<font size='3' color='#8b9099'>DevOps · SRE · Platform Engineering</font>"
            textFormat: Text.RichText
        }
    }

    Slide {
        Text {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            color: "#e6e8ec"
            font.pixelSize: 18
            text: "Containers sem root e sem daemon\n\n" +
                  "<font size='3' color='#8b9099'>Delonix Runtime e Podman, com cgroups delegados.\n" +
                  "O CLI do docker funciona — o daemon fica desligado.</font>"
            textFormat: Text.RichText
        }
    }

    Slide {
        Text {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            color: "#e6e8ec"
            font.pixelSize: 18
            text: "Afinado antes do primeiro login\n\n" +
                  "<font size='3' color='#8b9099'>Escalonador de I/O por tipo de disco, BBR com fq,\n" +
                  "zram, e um perfil térmico escolhido pelo teu hardware.</font>"
            textFormat: Text.RichText
        }
    }
}

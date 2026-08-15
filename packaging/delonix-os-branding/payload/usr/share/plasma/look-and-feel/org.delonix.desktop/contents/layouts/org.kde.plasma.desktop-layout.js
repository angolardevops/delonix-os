// DelonixOS — layout por omissão do Plasma.
//
// Um único painel em baixo, 44 px, com o mínimo: lançador, janelas, bandeja e
// relógio. Nada de widgets decorativos — o ecrã é para terminais e dashboards.

var desktopsArray = desktops();
for (var i = 0; i < desktopsArray.length; i++) {
    desktopsArray[i].wallpaperPlugin = "org.kde.image";
    desktopsArray[i].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktopsArray[i].writeConfig("Image", "Delonix");
    desktopsArray[i].writeConfig("FillMode", "2");
}

var panel = new Panel("org.kde.panel");
panel.location = "bottom";
panel.height = 44;
panel.alignment = "center";

panel.addWidget("org.kde.plasma.kickoff");
panel.addWidget("org.kde.plasma.pager");

var tasks = panel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:kitty.desktop",
    "applications:firefox.desktop",
    "applications:org.kde.kate.desktop"
].join(","));
tasks.writeConfig("showOnlyCurrentDesktop", false);
tasks.writeConfig("groupingStrategy", 1);

panel.addWidget("org.kde.plasma.marginsseparator");
panel.addWidget("org.kde.plasma.systemmonitor.cpucore");
panel.addWidget("org.kde.plasma.systemtray");

var clock = panel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateFormat", "isoDate");   // 2026-08-14 — logs e datas iguais
clock.writeConfig("use24hFormat", 2);
clock.writeConfig("showSeconds", false);

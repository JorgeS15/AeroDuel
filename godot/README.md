# AeroDuel: app Android (Godot 4)

Versão a sério do AeroDuel, feita em **Godot 4.5**. Por agora (fase 1) tem o mesmo que o protótipo web:
- voo com perda de velocidade, descolagem e aterragem;
- tiro, e reparação ao passar pelo hangar;
- paraquedas que se pode rasgar a tiro, e piloto que corre até ao hangar;
- bot com 3 dificuldades;
- controlos táteis com multitoque, vibração e sons.

## Instalar no telemóvel

Cada build gera um APK que se descarrega diretamente, sem `.zip`:

- **Versão mais recente (`main`):** https://github.com/JorgeS15/AeroDuel/releases/download/latest/AeroDuel.apk
- **Versão de teste de um PR:** `…/releases/download/pr-<número>/AeroDuel.apk`, também listada em **Releases**.

Abre o link no telemóvel, com sessão iniciada no GitHub enquanto o repositório for privado, e abre o `AeroDuel.apk`. Da primeira vez, o Android pede para autorizar a instalação de apps desta origem. O APK fica também em **Actions → Android APK** como artefacto `.zip`.

## Abrir no computador

1. Instala o [Godot 4.5](https://godotengine.org/download), a versão normal e não a .NET.
2. No Godot, faz **Import** e escolhe `godot/project.godot`.
3. Carrega em **F5** para jogar no computador, com o teclado: ← → rodar, Espaço disparar, E saltar, P pausa.

Para exportar para Android a partir do editor, segue o guia oficial ["Exporting for Android"](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html). Precisas do Android SDK e de uma chave de debug.

## Estrutura

```
godot/
├── data/planes/       aviões (.tres): cada modelo novo é um ficheiro com velocidade, rotação, vida e cadência de tiro
├── scenes/main.tscn   cena principal
├── scripts/
│   ├── core/config.gd     constantes do mundo e utilitários (volta ao mundo, ângulos)
│   ├── data/              tipos de dados (PlaneType)
│   ├── game/              simulação: world, airplane, pilot, bot_brain, fx_layer, background
│   ├── ui/                hud, main_menu, touch_button
│   └── autoload/          Game (definições, teclas, tema) e Sfx (sons gerados por código)
└── tests/
    ├── sim_test.tscn      10 min de bot contra bot por dificuldade, com limites mínimos (corre no CI)
    └── screenshots.tscn   capturas de ecrã do menu e do jogo
```

Correr o teste no terminal:

```
godot --headless --path godot res://tests/sim_test.tscn
```

## Notas de desenho

- **Passo fixo:** a simulação corre a 60 passos por segundo (`_physics_process`), por isso o comportamento é igual em qualquer telemóvel.
- **Desenho:** por agora é feito em código (`_draw`). Mais tarde troca-se por sprites sem mexer na física.
- **Efeitos:** som, partículas e mensagens passam todos por `World.fx()`. É esse o ponto que o multiplayer vai usar para reenviar eventos ao outro telemóvel.
- **Ecrã:** o mundo lógico tem 384×216 e é escalado para o ecrã (`canvas_items`). Em telemóveis mais compridos que 16:9 ficam barras laterais. Ajusta-se numa fase seguinte.

# AeroDuel: app Android (Godot 4)

Versão a sério do AeroDuel, feita em **Godot 4.5**. O que já tem:

- **Voo:** perda de velocidade, descolagem e aterragem, e reparação ao passar pelo hangar. Se virares o avião de costas, ele continua de costas.
- **Paraquedas:** pode rasgar-se a tiro; no chão, o piloto corre até ao hangar.
- **4 aviões**, escolhidos no menu com ◀ ▶:

| Avião | Características |
|---|---|
| Biplano | Equilibrado, aguenta 3 tiros |
| Caça | Rápido e com rotação apertada, mas só aguenta 2 tiros |
| Bombardeiro | Lento e pesado: aguenta 5 tiros e tem metralhadora traseira |
| Triplano | Sobe como ninguém e quase não entra em perda, mas é lento |

- **Powerups:** caem caixas de paraquedas e apanham-se a voar contra elas.

| Letra | Powerup | Efeito |
|---|---|---|
| E | Escudo | Absorve 3 tiros |
| 3 | Tiro triplo | Leque de balas durante 8 s |
| T | Turbo | Mais motor e mais rotação durante 8 s |
| + | Reparação | Vida cheia |
| B | Bombas | 2 bombas: botão BOMBA ou tecla B. Rebentam no chão ou ao tocar num avião e apanham aviões e pilotos à volta |

- **Campanha:** 12 missões em 3 regiões, cada uma com até 3 estrelas: cumprir, uma condição extra e um tempo de referência (ou um número de abates). As regiões 2 e 3 abrem com 6 e 14 estrelas.
  - **Região 1, Costa:** *Primeiro voo* (abater 3 aviões), *Balões de observação* (4 balões contra o relógio), *Defender o hangar* (bombardeiros) e *O Ás Negro*.
  - **Região 2, Montanhas, com vento** que empurra aviões, paraquedas e caixas: *Vento cruzado*, *Balões na serra*, *Aguentar a posição* (resistir 1 min 15 s) e *Raide na montanha*.
  - **Região 3, Frente, de noite** (vê-se pior): *Patrulha noturna*, *Balões ao luar*, *Última defesa* e *O regresso do Ás*.
- **Progresso** (guardado no telemóvel): moedas por abates, missões e estrelas novas. No **hangar** compras aviões, 3 melhorias por avião (motor, blindagem, metralhadora) e pinturas. Na campanha só podes usar os aviões que compraste; no duelo livre estão todos disponíveis.
- **Multijogador na mesma rede Wi-Fi** (ou com um telemóvel a fazer hotspot): um telemóvel cria o jogo e o outro encontra-o na lista ou liga-se pelo IP. Duelo até 10 pontos, todos os aviões disponíveis, sem moedas.
- **Bot:** 3 dificuldades e o "ás" das missões. Também vai buscar caixas e bombardeia alvos no chão.
- **Ecrã inteiro:** a largura do mundo acompanha o formato do telemóvel, sem barras pretas.
- **Controlos táteis** baixos, nos cantos, com zona de toque maior do que o desenho, e quase transparentes quando há um avião por trás. Multitoque, vibração e sons.
- **Builds de debug:** botão "Bot: ataca/alvo", versão do build no menu e aviso de atualização.

Para criar um avião novo, junta um `.tres` a `data/planes/` e o id a `World.PLANE_IDS`. Os números dos powerups estão em `scripts/data/powerups.gd`. As missões estão em `scripts/data/campaign.gd`, e os preços e melhorias em `scripts/autoload/progress.gd`.

## Instalar no telemóvel

Cada build gera um APK que se descarrega diretamente, sem `.zip`:

- **Versão mais recente (`main`):** https://github.com/JorgeS15/AeroDuel/releases/download/latest/AeroDuel.apk
- **Versão de desenvolvimento (`dev`, com tudo o que está a ser testado):** https://github.com/JorgeS15/AeroDuel/releases/download/dev/AeroDuel.apk
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
│   ├── net/               net_sync: fotografias do jogo para o multijogador
│   └── autoload/          Game (definições, teclas, tema), Sfx (sons gerados por código), Net (multijogador), Progress, Updater
└── tests/
    ├── sim_test.tscn      cada avião contra cada avião, 10 min por dificuldade e as missões jogadas por um bot (corre no CI)
    ├── net_test.tscn      multijogador com dois processos (anfitrião e convidado), cada um jogado por um bot (corre no CI)
    └── screenshots.tscn   capturas de ecrã do menu e do jogo
```

Correr o teste no terminal:

```
godot --headless --path godot res://tests/sim_test.tscn
```

## Notas de desenho

- **Passo fixo:** a simulação corre a 60 passos por segundo (`_physics_process`), por isso o comportamento é igual em qualquer telemóvel.
- **Desenho:** por agora é feito em código (`_draw`). Mais tarde troca-se por sprites sem mexer na física.
- **Efeitos:** som, partículas e mensagens passam todos por `World.fx()`. No multijogador, o anfitrião reenvia-os ao outro telemóvel.
- **Multijogador** (`autoload/net.gd`, `net/net_sync.gd`): o anfitrião corre a simulação (modo `versus`) e envia 30 fotografias por segundo por ENet (porta UDP 27450). O convidado (modo `remote`) não simula: mostra as fotografias com 80 ms de atraso, a interpolar entre elas, e envia os seus controlos a cada passo. Os jogos anunciam-se por difusão UDP na porta 27451. A largura do mundo fica a do ecrã mais estreito; o mais largo mostra barras dos lados.
- **Ecrã:** a altura lógica é sempre 216. A largura (`Config.W`, no mínimo 384) segue o formato do ecrã (`keep_height`).

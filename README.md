# AeroDuel ✈️

Protótipo de um jogo 2D de combate de biplanos, inspirado nos clássicos *Biplanes* / *Bluetooth Biplanes* dos telemóveis Java.

Tu (azul) contra um bot (vermelho). Abate o avião inimigo e, se fores atingido, salta de paraquedas e corre até ao teu hangar para ires buscar outro avião.

## Como jogar

Abre o `index.html` num browser. Não precisa de servidor nem de instalar nada.

Para jogar no telemóvel, ativa o **GitHub Pages** no repositório (Settings → Pages → Branch `main` / root) e abre o link no Android. Põe o telemóvel na horizontal. Se quiseres, adiciona o jogo ao ecrã principal.

| Ação | Ecrã tátil | Teclado |
|---|---|---|
| Rodar o avião | ↺ ↻ | ← → ou A D |
| Disparar | FOGO | Espaço ou J |
| Saltar de paraquedas | SALTAR | E ou K |
| Pausa | ⏸ | P ou Esc |

Com o paraquedas aberto, guias a descida com ↺ ↻. No chão, o piloto anda com os mesmos botões.

## Regras e física

- O motor está sempre ligado. A subir perdes velocidade e a descer ganhas.
- Abaixo de uma certa velocidade o avião **entra em perda**: o nariz cai e o avião começa a cair. Para recuperar, aponta para baixo.
- **Descolar:** espera que o avião ganhe velocidade e puxa o nariz para cima.
- **Aterrar:** toca no chão quase na horizontal. Se passares pelo teu hangar, o avião fica reparado.
- Cada avião aguenta 3 tiros. Ao terceiro começa a cair a arder.
- O paraquedas pode ser rasgado a tiro, e o piloto pode ser abatido no ar ou no chão.
- **Pontos:** avião destruído +1, piloto eliminado +1. Se ficares dentro do avião quando ele cai, o adversário ganha os dois pontos. Ganha quem chegar primeiro a 10.
- O mundo dá a volta: se saíres por um lado do ecrã, apareces do outro.

## Bot

O bot tem três níveis: Fácil, Normal e Difícil. Em cada nível muda o tempo de reação, o erro de pontaria, o alcance e a vontade de disparar. A partir do Normal também persegue pilotos de paraquedas.

O bot:
- aponta para a posição prevista do alvo;
- evita mergulhar perto do chão e entrar em perda;
- salta quando o avião é abatido;
- corre para o hangar quando está no chão.

## Estrutura

- `index.html`: página, HUD, menus e botões táteis
- `style.css`: estilos
- `game.js`: tudo o resto (física, IA, desenho, som com WebAudio)

Os valores de afinação ficam no topo de `game.js` (`THRUST`, `DRAG`, `STALL`, `TAKEOFF`, `TURN`, `MAX_HP`, `WIN_SCORE`…) e as dificuldades em `DIFFS`.

## Próximos passos possíveis

- Portar para Godot 4 e exportar como APK Android.
- Sprites em pixel art e mais sons.
- Obstáculos (torres, árvores), bombas, vento.
- Multijogador local (dois jogadores no mesmo ecrã) ou online.

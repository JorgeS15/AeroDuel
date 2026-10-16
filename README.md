# AeroDuel ✈️

Protótipo de um jogo 2D de combate de biplanos, inspirado nos clássicos *Biplanes* / *Bluetooth Biplanes* dos telemóveis Java.

Joga contra um bot ou online contra outra pessoa (1 contra 1). Abate o avião inimigo e, se fores atingido, salta de paraquedas e corre até ao teu hangar para ires buscar outro avião.

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

## Jogo online

1. Um jogador escolhe **Criar sala online** e recebe um código de 4 letras (por exemplo `K7QF`).
2. Envia o código ao adversário, ou carrega em **Partilhar link**. O link já leva o código (`…/index.html#K7QF`).
3. O outro jogador escolhe **Entrar numa sala** e escreve o código.

Quem cria a sala joga de azul e quem entra joga de vermelho. Os dois precisam de internet. O jogo tem de estar alojado num endereço `https://`, por exemplo no GitHub Pages: a partir de um ficheiro aberto localmente o online pode não funcionar.

### Como funciona

- A ligação é feita com o [PeerJS](https://peerjs.com/) (WebRTC). O servidor público gratuito do PeerJS só serve para os dois telemóveis se encontrarem. Depois, os dados vão diretamente de um para o outro.
- **O anfitrião manda no jogo:** simula a física, as balas, as colisões e os pontos. O convidado só envia os seus controlos.
- O anfitrião envia o estado do jogo 25 vezes por segundo. O convidado desenha ligeiramente atrasado (90 ms), a interpolar entre estados, para o movimento ficar suave.
- Os sons, explosões e mensagens viajam como eventos, e cada ecrã mostra-os do seu ponto de vista ("Abateste…" ou "Perdeste…").
- Se o adversário sair ou a ligação cair durante mais de 5 segundos, o jogo volta ao menu com um aviso.
- No modo online não há pausa.

Para usar um PeerServer próprio em vez do público, junta `?peerhost=servidor:porta` ao endereço (por exemplo `?peerhost=localhost:9000` para testes).

**Limitação conhecida:** algumas redes muito restritivas (certas redes de empresas ou de operadores móveis) não deixam fazer ligações diretas. Nesses casos seria preciso configurar um servidor TURN.

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
- `net.js`: salas online e ligação PeerJS
- `game.js`: tudo o resto (física, IA, rede do anfitrião e do convidado, desenho, som com WebAudio)

Os valores de afinação ficam no topo de `game.js` (`THRUST`, `DRAG`, `STALL`, `TAKEOFF`, `TURN`, `MAX_HP`, `WIN_SCORE`…) e as dificuldades em `DIFFS`.

## Próximos passos possíveis

- Portar para Godot 4 e exportar como APK Android.
- Sprites em pixel art e mais sons.
- Obstáculos (torres, árvores), bombas, vento.
- Multijogador local (dois jogadores no mesmo ecrã).
- Previsão local do avião do convidado, para reduzir o atraso nos controlos.
- App Android instalável (PWA, ou Capacitor/TWA para a Play Store).

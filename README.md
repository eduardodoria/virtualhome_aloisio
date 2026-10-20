# Casa Aloísio — passeio virtual

Passeio 3D pela casa do Aloísio, em Caípe Velho, São Cristóvão (SE), feito com a
[Doriax Engine](https://github.com/doriaxengine/doriax). A casa segue o projeto do SketchUp e está
no lugar dela de verdade, com o terreno, o rio e a mata em volta. Dá para escolher o dia e a hora:
o sol aparece onde estaria naquele momento e, quando escurece, as luzes da casa acendem.

## Abrir

- **No navegador:** <https://eduardodoria.github.io/virtualhome_aloisio/>. Baixa cerca de 175 MB na
  primeira vez. Em celular e tablet aparecem controles na tela.
- **Linux:** [baixar](https://github.com/eduardodoria/virtualhome_aloisio/archive/refs/heads/linux.zip), extrair e rodar `Casa_Aloisio`.
- **Windows:** [baixar](https://github.com/eduardodoria/virtualhome_aloisio/archive/refs/heads/windows.zip), extrair e rodar `Casa_Aloisio.exe`.
- **macOS:** [baixar](https://github.com/eduardodoria/virtualhome_aloisio/archive/refs/heads/macos.zip),
  extrair e rodar `Casa_Aloisio`. O executável não é assinado: se o macOS bloquear, libere em
  Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim.

## Controles

| Tecla | O que faz |
| --- | --- |
| W A S D ou setas | Andar |
| Shift | Correr |
| Botão direito do mouse | Olhar em volta (segure e arraste) |
| Tab | Prende o mouse para olhar sem segurar o botão; aperte de novo para soltar |
| F | Liga e desliga o voo (Espaço ou E sobe, C ou Q desce) |
| 1 a 6 | Pontos de vista: rua, entrada, sala, varanda, vista aérea e quintal |
| [ e ] | Volta ou avança uma hora |
| , e . | Volta ou avança um dia |
| T | Muda a velocidade do tempo |
| L | Luzes da casa: automático, ligadas ou desligadas |
| M | Liga e desliga o som |
| H | Abre e fecha o painel de data e hora |
| F3 | Abre e fecha o painel de desempenho |

Com um controle (gamepad) conectado:

| Controle (Xbox / PlayStation) | O que faz |
| --- | --- |
| Analógico esquerdo | Andar (mais rápido quanto mais inclinado) |
| Analógico direito | Olhar em volta |
| RT / R2, ou apertar o analógico esquerdo | Correr |
| Y / △ | Liga e desliga o voo (A / ✕ sobe, B / ○ desce) |
| LB / L1 e RB / R1 | Ponto de vista anterior e próximo |
| Direcional ← → | Volta ou avança uma hora |
| Direcional ↑ ↓ | Avança ou volta um dia |
| X / □ | Luzes da casa |
| Start / Options | Abre e fecha o painel de data e hora |
| Back / Share | Liga e desliga o som |

Em celular e tablet aparecem controles na tela:

- o joystick embaixo à esquerda anda, mais rápido quanto mais longe do centro;
- arrastar o dedo no resto da tela olha em volta;
- Correr e Voar ficam embaixo à direita, e Subir e Descer aparecem durante o voo;
- "Ir para", no alto à direita, leva ao próximo ponto de vista.

Esses controles só aparecem em aparelhos com tela de toque.

O relógio no canto de baixo, à esquerda, abre o painel de data e hora. Ele mostra a data, a
hora, a altura e a direção do sol e quanto da lua está iluminado. Os botões mudam o dia, o mês e
a hora, a barra escolhe qualquer hora do dia e "Agora" volta para o horário atual. No modo
automático as luzes acendem quando o sol se põe.

Ao lado do relógio, o botão com um medidor abre o painel de desempenho: mostra os quadros por
segundo e deixa reduzir a resolução, as sombras e a distância da vegetação, para máquinas mais
fracas. Também liga a oclusão de ambiente (SSAO) e os reflexos em tela (SSR), que começam
desligados porque pesam bastante.

## Este repositório

Só recebe os builds, publicados pelo CI do projeto (que fica num repositório privado). Cada branch
tem um único commit, trocado a cada build:

| Branch | Conteúdo |
| --- | --- |
| `gh-pages` | Versão web (GitHub Pages) |
| `linux`, `windows`, `macos` | Versões desktop |

## Créditos

- Texturas e alguns modelos: [Poly Haven](https://polyhaven.com) (CC0).
- Relevo: Copernicus DEM GLO-30, © DLR e.V. 2010-2014 e © Airbus Defence and Space GmbH
  2014-2018, fornecido pelo programa Copernicus da União Europeia e pela ESA.
- Imagens de satélite: contém dados modificados do Copernicus Sentinel (2026).
- Ruas: © colaboradores do [OpenStreetMap](https://www.openstreetmap.org/copyright).
- Sons (CC0, [Freesound](https://freesound.org)): Brazil Pantanal insects birds (Martin.Sadoux),
  Coró-Coró e Bem-te-vi (dtmendes), Night in the countryside in Brazil (felix.blume),
  steps_dry_grass (Mystikuum), snd_footsteps_grass (jevans27), passos em piso de daboy291 e
  soundmary.

# Fil rouge du testeur : démo ForYield sur Arc testnet

Objectif : reproduire seul, en une trentaine de minutes, ce que montre la démo. On déposera de
l'USDC dans le coffre ForYield, on vérifiera qu'il est placé chez Morpho dans la même
transaction, puis on rachètera ses parts. Tout se fait depuis un navigateur, sans ligne de
commande. La partie 6, facultative, rejoue les tests pour un profil développeur.

Tout se passe sur **Arc testnet** : les jetons n'ont aucune valeur et rien n'est irréversible
pour ForYield.

## Repères

| Élément | Adresse | Lien |
|---|---|---|
| Coffre USDC « ForYield Arc USDC » (fyUSDC) | `0xBbc099E29069e71C1A52C2e9d74328096Fc4e4a7` | [explorateur](https://explorer.testnet.arc.io/address/0xBbc099E29069e71C1A52C2e9d74328096Fc4e4a7) |
| Coffre EURC « ForYield Arc EURC » (fyEURC) | `0x623B4e264CB217763dDD71a1ec597c0926Cb902c` | [explorateur](https://explorer.testnet.arc.io/address/0x623B4e264CB217763dDD71a1ec597c0926Cb902c) |
| Cible Morpho Vault V2 (USDC) | `0x76b022B083F00e094feB1DFf5a89E60cF1c52e27` | [explorateur](https://explorer.testnet.arc.io/address/0x76b022B083F00e094feB1DFf5a89E60cF1c52e27) |
| Cible Morpho Vault V2 (EURC) | `0x046CE778D030B0Bb348dd8fDa4751B2281081AE4` | [explorateur](https://explorer.testnet.arc.io/address/0x046CE778D030B0Bb348dd8fDa4751B2281081AE4) |
| USDC (Arc testnet) | `0x3600000000000000000000000000000000000000` | [explorateur](https://explorer.testnet.arc.io/address/0x3600000000000000000000000000000000000000) |
| EURC (Arc testnet) | `0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a` | [explorateur](https://explorer.testnet.arc.io/address/0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a) |

**Unités.** L'USDC et l'EURC comptent 6 décimales dans les formulaires de l'explorateur :
1 USDC s'écrit `1000000`. Les parts du coffre en comptent 12 : 1 USDC déposé donne environ
`1000000000000` parts.

## 1. Préparer le portefeuille

1. Installer MetaMask (ou un autre portefeuille de navigateur) et créer un compte dédié aux
   tests. N'utiliser aucun compte qui détient de vrais fonds.
2. Ajouter Arc testnet : ouvrir l'[explorateur](https://explorer.testnet.arc.io) et cliquer
   sur **Add Arc Testnet**, en haut à droite. Paramètres pour un ajout manuel :
   réseau `Arc Testnet`, RPC `https://rpc.testnet.arc.io`, chain id `5042002`, symbole `USDC`,
   explorateur `https://explorer.testnet.arc.io`.
3. Sur [faucet.circle.com](https://faucet.circle.com), choisir **Arc Testnet** et demander de
   l'USDC, puis de l'EURC, vers son adresse.

**À constater :** le solde affiché par MetaMask est en USDC. Sur Arc, l'USDC est aussi le
jeton de gas : les frais de chaque transaction sont prélevés en USDC, pour quelques
millièmes de dollar.

## 2. Inspecter le coffre avant d'y toucher

Ouvrir la page du coffre USDC, onglet **Contract**.

- [ ] Le bandeau vert indique « Contract source code verified (exact match) ».
- [ ] Les arguments du constructeur montrent l'actif USDC, le nom « ForYield Arc USDC » et la
  cible Morpho `0x76b0…2e27`.

Onglet **Contract**, puis **Read/Write contract**, puis **Read**. Lire :

- [ ] `asset` renvoie `0x3600…0000` (USDC).
- [ ] `MORPHO_VAULT` renvoie `0x76b0…2e27`.
- [ ] `owner`, `guardian` et `RECOVERY_ADDRESS` renvoient trois adresses différentes.
- [ ] `paused` renvoie `false`.
- [ ] Noter `totalAssets` et `totalSupply` avant le test.

## 3. Déposer 1 USDC

**3.1 Approuver le coffre pour exactement 1 USDC.** Ouvrir la page du contrat USDC
`0x3600…0000`, onglet **Contract**, puis **Read/Write proxy** (l'USDC de Circle est un
contrat proxy). Cliquer sur **Connect your wallet**, puis appeler `approve` :

- `spender` : `0xBbc099E29069e71C1A52C2e9d74328096Fc4e4a7`
- `value` : `1000000`

**3.2 Déposer.** Revenir sur la page du coffre USDC, onglet **Read/Write contract**,
**Write**, **Connect your wallet**, puis appeler `deposit` :

- `assets` : `1000000`
- `receiver` : sa propre adresse

**À constater sur la page de la transaction de dépôt** (lien proposé par MetaMask ou par
l'explorateur) :

- [ ] Statut « Success », méthode `deposit`.
- [ ] Deux transferts d'USDC dans la même transaction : de son adresse vers MorphoYieldVault,
  puis de MorphoYieldVault vers VaultV2 (la cible Morpho). Le dépôt est placé immédiatement.
- [ ] Des parts `fyUSDC` sont créées vers son adresse. Une autre création, affichée
  « Unnamed token », va vers MorphoYieldVault : ce sont les parts de la cible Morpho, qui
  n'a pas de nom.
- [ ] Les frais de transaction sont indiqués en USDC.

**Puis, en lecture :**

- [ ] Sur le coffre, `balanceOf(son adresse)` renvoie environ `1000000000000`.
- [ ] Sur le contrat USDC, `allowance(owner = coffre 0xBbc0…e4a7, spender = cible 0x76b0…2e27)`
  renvoie `0` : le coffre ne laisse aucune approbation en place chez Morpho.
- [ ] Sur le contrat USDC, `allowance(owner = son adresse, spender = coffre)` renvoie `0` :
  l'approbation de l'étape 3.1 a été consommée en entier.
- [ ] Sur le coffre, `totalAssets` a augmenté de `1000000` et le solde USDC du coffre lui-même
  est à `0` : tout est chez Morpho.

## 4. Racheter ses parts

Sur le coffre, **Write**, appeler `redeem` :

- `shares` : la valeur lue par `balanceOf(son adresse)`
- `receiver` : sa propre adresse
- `owner` : sa propre adresse

**À constater :**

- [ ] Statut « Success ». L'USDC revient de VaultV2 vers MorphoYieldVault, puis de
  MorphoYieldVault vers son adresse.
- [ ] Montant reçu : 1 USDC, à un ou deux millionièmes près. Les arrondis jouent toujours en
  faveur du coffre, jamais du déposant.
- [ ] `balanceOf(son adresse)` renvoie `0`.

Sur testnet, la cible Morpho n'est branchée sur aucun marché de prêt : elle ne rapporte rien,
et c'est attendu. Le rendement réel est démontré contre un vault Morpho curaté du mainnet, par
le test de la partie 6.

## 5. Ce qui doit échouer

Ces essais doivent être refusés. MetaMask signale en général l'échec avant l'envoi : il suffit
alors de noter le message sans envoyer la transaction.

- [ ] `deposit` sans approbation préalable : refus par le contrat USDC de Circle
  (« ERC20: transfer amount exceeds allowance »).
- [ ] `redeem` pour le compte d'un autre détenteur, par exemple `shares` `1000000`,
  `receiver` sa propre adresse, `owner` le déposant de la démo
  `0x91405144F7ac4E9CcC26C32fbc475535d6110837` : refus (`ERC20InsufficientAllowance`).
  Personne ne peut racheter les parts d'autrui.
- [ ] `pause`, `emergencyDeallocate` ou `emergencyWithdraw` depuis son compte : refus
  (`NotOwnerOrGuardian`).
- [ ] `setGuardian` ou `unpause` depuis son compte : refus (`OwnableUnauthorizedAccount`).

## 6. Facultatif : rejouer les tests (profil développeur)

Prérequis : [Foundry](https://getfoundry.sh) et, pour le dernier test,
[Arc Foundry](https://github.com/circlefin/arc-foundry).

```bash
git clone --recurse-submodules https://github.com/Foryield/arc-yield-vault.git
cd arc-yield-vault
forge test
arc-forge test --isolate --match-path test/fork/MorphoArcMainnet.fork.t.sol \
  --fork-url https://rpc.mainnet.arc.io
```

- [ ] `forge test` : toutes les suites passent, le test fork est marqué « skipped » (il ne
  tourne que sur une copie d'Arc).
- [ ] Le test fork passe : 9 000 USDC déposés dans le vrai vault Morpho Galaxy USDC, sur une
  copie locale du mainnet, rapportent un intérêt réel après un an simulé. Rien n'est envoyé
  sur le mainnet.

## 7. Recommencer avec l'EURC (facultatif)

Mêmes étapes 3 et 4 avec le contrat EURC `0x89B5…D72a` pour l'approbation et le coffre EURC
`0x623B…902c` pour le dépôt et le rachat. La cible Morpho est alors `0x046C…1AE4`.

## Fiche de résultat

Pour chaque étape, noter le hash de transaction (ou le message d'erreur attendu) et une
capture d'écran de la page de l'explorateur.

| Étape | Résultat attendu | Hash ou message | OK |
|---|---|---|---|
| 3.1 approve USDC | Success | | |
| 3.2 deposit 1 USDC | Success, deux transferts d'USDC dans la même transaction | | |
| Lectures après dépôt | allowances à 0, solde du coffre à 0 | | |
| 4 redeem | Success, environ 1 USDC reçu | | |
| 5 deposit sans approve | refusé | | |
| 5 redeem pour autrui | refusé | | |
| 5 pause depuis son compte | refusé | | |
| 6 tests (facultatif) | tout passe | | |

## Que signaler

Toute différence avec un point « À constater », tout message d'erreur inattendu, et tout
écart de montant supérieur à deux millionièmes d'USDC. Joindre le hash de transaction et la
capture correspondante.

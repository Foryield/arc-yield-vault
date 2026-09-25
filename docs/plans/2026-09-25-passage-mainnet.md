# Passage sur Arc mainnet : état et reste à faire

Date : 2026-09-25. Destiné à qui reprend le sujet. Plan de référence de la tranche testnet : [2026-09-21-arc-morpho-vault-design.md](./2026-09-21-arc-morpho-vault-design.md).

## 1. Objet et périmètre

La direction de ForYield a donné le 2026-09-23 son accord pour passer le coffre sur Arc mainnet (chain id 5042). Le périmètre retenu est étroit : **le coffre ne reçoit que le capital propre de ForYield**. C'est une démonstration pour le grant Circle, pas une offre. Le dépôt GitHub étant public, rien ne doit laisser croire à un tiers qu'il peut y déposer pour du rendement. D'où une restriction on-chain des dépôts, un front en lecture seule ne suffisant pas.

Livrables attendus :

1. `MorphoYieldVault` USDC déployé sur Arc mainnet, source vérifiée (Sourcify, puis dépôt manuel du JSON standard sur `explorer.arc.io`).
2. Owner = portefeuille de custody ForYield, guardian et adresse de recovery posés au constructeur.
3. Un `deposit` puis un `redeem` en capital propre, signés par l'owner.
4. Le script CCTP exécuté une fois pour de vrai de Base vers Arc mainnet (hash du burn sur Base, hash du mint sur Arc).
5. Un journal de preuves daté et les captures, au même format que la tranche testnet.

Hors périmètre : front mainnet (la démo `arc.for-yield.com` reste sur testnet), dépôts de tiers, StableFX, Gateway, adaptateur Aave V4.

## 2. Déjà fait (commits `cd46bf0` à `30e756b`, sur `main`)

- **Dépôts réservés à l'owner** : `OWNER_ONLY_DEPOSITS`, immuable, fixé au constructeur. `maxDeposit` et `maxMint` renvoient 0 pour tout autre bénéficiaire, un dépôt d'un autre appelant échoue avec `DepositNotAllowed`. Les sorties restent ouvertes aux détenteurs de parts.
- **`script/Deploy.s.sol`** diffuse depuis une clé de déploiement sans aucun rôle : owner, guardian et recovery sont posés par le constructeur. Aucune signature `acceptOwnership` ou `setGuardian` n'est donc nécessaire côté custody. Sur mainnet, le script force `OWNER_ONLY_DEPOSITS` à vrai et refuse toute cible Morpho dont une des quatre gates est posée.
- **CCTP** : `NETWORK=mainnet` dans `scripts/cctp/base-sepolia-to-arc.ts` (adresses Base et Arc mainnet contrôlées on-chain le 2026-09-23).
- **README** : sections déploiement mainnet et CCTP mainnet.
- **Test sur copie du mainnet** : `test/fork/MorphoArcMainnet.fork.t.sol`, contre Galaxy USDC réel, configuré comme sur mainnet (dépôts réservés à l'owner). Il tourne chaque semaine en CI.

## 3. Décisions ouvertes, côté direction

Elles bloquent le déploiement, pas le code.

1. **Cible Morpho (curateur)** : c'est un nom qui apparaîtra dans le dossier du grant. Voir §4.
2. **Montant du capital propre** pour le dépôt et le retrait de preuve.
3. **Portefeuille de custody owner**, et sa capacité à signer des transactions brutes (calldata fournie par `cast calldata`, voir README, section Mainnet).
4. **Adresses du guardian et de la recovery** : trois adresses distinctes exigées par le contrat. La recovery est immuable et reçoit tout l'actif en cas d'évacuation : elle doit être un portefeuille maîtrisé à long terme, idéalement un multisig.
5. **Coffre EURC** : le déployer ou non. La cible EURC la plus liquide rapporte environ 0 %.

## 4. Cibles Morpho relevées le 2026-09-25

Source : API Morpho (`blue-api.morpho.org/graphql`, `vaultV2s` sur `chainId_in: [5042]`), gates et actif contrôlés par `cast call` sur `https://rpc.mainnet.arc.io` (bloc 22 658 162).

| Vault V2 | Adresse | Actif | Encours | Liquidité | APY net | Gates |
|---|---|---|---|---|---|---|
| Galaxy USDC | `0x8E357432CC12ff425c36432F312968aEb16112AF` | USDC | 79,8 M$ | 57,1 M$ | 0,05 % | aucune |
| Keyrock Prime USDC | `0x5bEfAb92a5A3D60F578Cb51EEb4e4FD50a1e3123` | USDC | 75,0 M$ | 57,1 M$ | 0,06 % | aucune |
| Bitwise Premium RWA USDC | `0x7610094B846657dCF166D59e42973db52c7015F9` | USDC | 0,36 M$ | 0,24 M$ | 1,37 % | aucune |
| Galaxy EURC | `0x389abDf4355e0cF4f19298179991705a98f21c18` | EURC | 0,57 M$ | 0,57 M$ | ~0 % | aucune |
| Steakhouse Prime EURC | `0xbeef00be37BdE921BAE06fad223125BAB16c41D1` | EURC | 0,01 M$ | 0,01 M$ | 0 % | aucune |

Lecture :

- Les deux cibles USDC liquides ne rapportent presque rien. La courbe de rendement de la vidéo sera plate : le dire, ne pas le maquiller.
- Bitwise est passé de 130 $ de liquidité le 2026-09-23 à 0,24 M$ : ces chiffres bougent vite. Un rendement plus élevé sur une petite cible expose à des retraits qui échouent faute de liquidité.
- Plusieurs vaults portent le même nom avec quelques dollars d'encours (instances de test des curateurs). **Toujours prendre la cible par son adresse, jamais par son nom.**
- **À refaire le jour du déploiement**, APY, liquidité et gates compris. Une gate posée après dépôt bloque toute sortie, `forceDeallocate` compris ; le script refuse une cible gatée au déploiement, mais rien ne protège d'une gate posée ensuite. Contrôle manuel :

```bash
for g in receiveSharesGate sendSharesGate receiveAssetsGate sendAssetsGate; do
  cast call <cible> "$g()(address)" --rpc-url https://rpc.mainnet.arc.io
done
```

## 5. Ordre de marche une fois les décisions prises

1. **Gas** : la clé de déploiement et la clé qui relaie le mint CCTP sur Arc ont besoin de quelques USDC natifs sur Arc mainnet. Il n'y a pas de faucet : prévoir une première alimentation (exchange qui sert Arc, ou un premier transfert CCTP vers la clé elle-même, qui doit alors déjà disposer de gas sur Arc).
2. **CCTP** : `NETWORK=mainnet`, `RECIPIENT` = portefeuille de custody, `AMOUNT` = capital propre plus une marge de gas. Noter les deux hashes. Le script reprend un transfert interrompu depuis son burn (`BURN_TX`).
3. **Déploiement** : `script/Deploy.s.sol` sur `--rpc-url arc`, commande dans le README. Contrôler ensuite `owner()`, `guardian()`, `RECOVERY_ADDRESS()` et `OWNER_ONLY_DEPOSITS()` par `cast call`, avant toute signature de la custody.
4. **Vérification de source** : le vérificateur Blockscout de `explorer.arc.io` est derrière un défi anti-robots. Publier sur Sourcify, puis déposer à la main `standard-input.json` sur l'explorateur avec les arguments de constructeur ABI-encodés. Commandes dans le README. Garder la capture de la page « verified ».
5. **Preuve de dépôt et de retrait** : trois signatures de la custody, dans l'ordre `approve` (vers l'USDC), `deposit`, `redeem`. Après le dépôt, relever `totalAssets()`, la position Morpho du coffre et `allowance(coffre, cible) == 0`.
6. **Journal de preuves** : créer `docs/evidence/a3-vault-mainnet.md` au format de `a1-vault-testnet.md` (date UTC, ce que ça prouve, hash et lien explorateur, adresse, statut de vérification, commit, empreinte du bytecode `cast code <coffre> | sha256sum`). Ajouter la ligne dans `docs/evidence/README.md`, dont la mention « testnet only » devient fausse.
7. **README** : l'introduction et la section Testnet deployments disent « nothing is deployed on mainnet ». Ajouter une section Mainnet deployment (adresse, cible, dépôts réservés à l'owner) et corriger ces phrases. Mettre à jour « Circle products used » et la Roadmap.

## 6. Pièges connus

- Les `maxDeposit/maxMint/maxWithdraw/maxRedeem` d'un Vault V2 renvoient toujours 0 : le coffre ne les lit jamais, n'y touchez pas.
- Un Vault V2 fige sa valorisation pour le reste d'une transaction : le test sur copie du mainnet exige `--isolate`, sans quoi aucun intérêt n'apparaît après `vm.warp`.
- USDC sur Arc est à la fois le gas natif (18 décimales) et un ERC-20 à `0x3600…0000` (6 décimales), sur le même solde. Le portefeuille owner paie son gas avec l'USDC qu'il dépose : ne jamais déposer le solde total.
- Forge vanille n'exécute pas ce précompilé : scripts et tests de copie avec Arc Foundry (`arc-forge`, `arc-anvil`).
- Forge 1.7.1 a déjà omis une suite de tests entière par son cache : `forge clean` avant de conclure sur un résumé de tests.
- Rien de privé dans ce dépôt public : ni nom de personne, ni configuration interne de custody, ni code d'un autre dépôt ForYield. Adresses publiques uniquement.

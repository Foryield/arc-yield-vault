# Arc YieldVault : conception et plan d'exécution

Date : 2026-09-21. Statut : validé le 2026-09-21 (architecture A, dépôts ouverts, seuil de couverture 95 %).

## 1. Objet

Un coffre ERC-4626 public, sous licence MIT, qui place l'USDC ou l'EURC déposé dans un vault Morpho Vault V2 sur Arc, la chaîne de Circle. Il sert de démonstration pour une candidature au Circle Developer Grants Program, sur le modèle de `Foryield/soroban-yield-vault` et `Foryield/solana-yield-vault` : un contrat, des tests, un journal de preuves on-chain, puis une base réutilisable plus tard.

Cadre fixé :

- **Réseau** : Arc testnet (chain id 5042002). Pas de déploiement mainnet dans cette tranche.
- **Administration** : clés locales (keystore Foundry chiffré), pas de custody tierce.
- **Code** : écrit dans ce dépôt, à partir d'OpenZeppelin et de Morpho. Aucun code importé d'un dépôt privé.
- **Hors périmètre** : démo web, onboarding wallet, StableFX, Gateway, adaptateur Aave V4, schéma d'événements de conformité. Ce sont des jalons du grant, présentés comme planifiés.

## 2. État vérifié du terrain (2026-09-21)

- Arc testnet répond (`eth_chainId` = `0x4cef52`). USDC y est à la fois le gas natif (18 décimales) et un ERC-20 prédéployé à `0x3600000000000000000000000000000000000000` (6 décimales, même solde). EURC testnet : `0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a`. Faucet : `faucet.circle.com`.
- **Morpho n'est pas déployé sur Arc testnet** : aucun code à l'adresse du cœur Morpho (`0x34CD04070dD72b14E241112F6d83812Df5Af7fCD`) sur testnet, et l'API Morpho répond `unsupported chainId "5042002"`. Sur mainnet (5042), Morpho Blue et plusieurs Vault V2 USDC et EURC sont ouverts, sans gate d'accès.
- Aave est déployé sur Arc en V4 seulement (architecture hub and spoke) : une intégration `IPool` V3 ne s'y applique pas. D'où le choix de Morpho, dont les vaults sont eux-mêmes des ERC-4626.
- CCTP v2 : Arc est le domaine 26, Base le domaine 6. Adresses testnet Arc : TokenMessengerV2 `0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA`, MessageTransmitterV2 `0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275`.
- Vérification de source testnet : Blockscout sur `explorer.testnet.arc.io`.

## 3. Spikes d'ouverture (à trancher avant le cœur)

| Spike | Question | Critère de sortie |
|---|---|---|
| S1 | Le bytecode Cancun (PUSH0, MCOPY, TSTORE) s'exécute-t-il sur Arc testnet ? | Déploiement d'un contrat minimal compilé en `cancun` et un appel réussi, sinon `evm_version` abaissée et notée |
| S2 | Un contrat peut-il faire `transferFrom` puis `approve` sur l'USDC prédéployé ? | Aller-retour réussi depuis un contrat de test sur testnet |
| S3 | Peut-on déployer nous-mêmes un vrai Morpho Vault V2 (code `morpho-org/vault-v2`) sur Arc testnet, sans adaptateur, pour servir de cible ? | Dépôt et retrait réussis sur l'instance, licence du code compatible avec un usage de test |
| S4 | CCTP v2 Base Sepolia vers Arc testnet : adresses Base Sepolia, endpoint d'attestation sandbox, EURC sur cette route | Un burn et un mint testnet réussis pour l'USDC ; statut EURC constaté |
| S5 | `arc-anvil` fork-t-il le mainnet Arc sous macOS arm64, et le RPC mainnet public accepte-t-il les lectures ? | Un test fork qui lit `totalAssets()` du vault Morpho mainnet visé |

Résultat (voir [2026-09-21-spikes.md](./2026-09-21-spikes.md)) : S3 a réussi, la cible testnet est un vrai Morpho Vault V2 déployé par nous, sans adaptateur, donc sans rendement. La hausse de NAV face à un vault Morpho curaté est prouvée par le test sur copie du mainnet (S5), sans rien déployer sur mainnet.

## 4. Architecture du contrat

### 4.1 Deux approches

**(A) Coffre de base abstrait et sous-classe par venue, dans le même dépôt.** `YieldVault` (abstrait) porte l'ERC-4626, la propriété en deux étapes, la pause, le guardian et l'évacuation d'urgence. `MorphoYieldVault` hérite et ajoute le placement dans un Vault V2 immuable, en surchargeant `totalAssets`, `_deposit` et `_withdraw`.
- Avantages : une seule frontière de confiance (un contrat déployé), aucun transfert entre contrats internes, surface d'audit minimale. Le futur adaptateur Aave V4 devient une deuxième sous-classe sans toucher la base.
- Inconvénients : changer de venue impose un nouveau déploiement (voulu : un coffre, une cible).
- Fichiers : `src/YieldVault.sol`, `src/MorphoYieldVault.sol`.

**(B) Coffre générique et stratégie externe branchée.** Le coffre délègue à un contrat `IStrategy` remplaçable par l'owner.
- Avantages : changement de venue sans redéploiement du coffre.
- Inconvénients : deux contrats, des approbations entre eux, un pouvoir owner de rebrancher la stratégie qui demanderait un timelock pour rester sûr. Plus de code et plus de surface pour une démo qui n'a qu'une venue.
- Fichiers : `src/YieldVault.sol`, `src/strategies/MorphoStrategy.sol`, `src/interfaces/IStrategy.sol`.

**Choix : (A).** La démo n'a qu'une venue par instance, les deux autres dépôts suivent la même règle (pool Blend fixé une fois à l'initialisation côté Soroban), et (B) ajoute un pouvoir de rebranchement qu'il faudrait ensuite encadrer par un timelock.

### 4.2 Surface de `YieldVault`

- OpenZeppelin `ERC4626`, `Ownable2Step`, `Pausable`, `SafeERC20`, version épinglée par submodule.
- Protection contre l'inflation au premier dépôt : décalage de décimales virtuel d'OpenZeppelin (`_decimalsOffset`), valeur fixée et testée.
- Rôles distincts, et contrôlés on-chain : `owner` (configuration), `guardian` (pause, désallocation d'urgence), `RECOVERY_ADDRESS` (immuable, seule destination de l'évacuation). Le constructeur refuse qu'une même adresse cumule deux rôles.
- `pause` : owner ou guardian ; `unpause` : owner seul. En pause, `max*` renvoient 0.
- Évacuation : `emergencyWithdraw()` exige la pause et envoie tout vers `RECOVERY_ADDRESS`, jamais vers une adresse passée en argument. Le coffre devient alors terminal : plus aucun dépôt ni retrait possible.

### 4.3 Surface de `MorphoYieldVault`

- `morphoVault` immuable ; le constructeur vérifie `morphoVault.asset() == asset()`.
- `totalAssets()` : `convertToAssets(parts Morpho détenues)` plus le solde idle. Arrondi vers le bas, donc favorable au coffre.
- **Les fonctions `max*` d'un Morpho Vault V2 renvoient toujours 0** (`maxDeposit`, `maxMint`, `maxWithdraw`, `maxRedeem` sont `pure` dans `VaultV2.sol`, lu le 2026-09-21 et constaté on-chain sur les vaults mainnet du §2). Le coffre ne les appelle donc jamais : elles ne disent rien de la capacité réelle.
- Dépôt : après encaissement, tout le solde idle est placé dans Morpho dans la même transaction, comme le coffre Soroban le fait avec Blend. Approbation du montant exact, allowance vérifiée à zéro après l'appel. Si Morpho refuse (plafond, gate, pause), la transaction entière échoue : aucun dépôt n'est accepté sans être placé, et il n'existe pas d'état idle silencieux à surveiller.
- Retrait : prélève d'abord l'idle, puis retire le manque de Morpho et vérifie le montant réellement reçu. Si Morpho n'a pas la liquidité, son `withdraw` échoue et la transaction entière avec, sans état modifié.
- `emergencyDeallocate()` (owner ou guardian) : rachète toutes les parts Morpho vers l'idle. Si Morpho manque de liquidité, la procédure opérationnelle `forceDeallocate` côté Morpho est documentée dans le README, pas implémentée.
- Aucune fonction ne tire des fonds d'une adresse fournie par l'appelant sans que ce soit `msg.sender` ou un owner ERC-4626 ayant donné son approbation (sémantique standard).

### 4.4 Qui peut déposer

- **(i) Dépôts ouverts** (ERC-4626 standard) : n'importe quel compte testnet peut déposer et racheter, comme la démo Soroban. Montre le produit sans intermédiaire.
- **(ii) Dépôts réservés à l'owner** : un wallet de pool dépose pour le compte de clients, comptés hors chaîne. Plus proche d'un modèle custodial poolé, mais la démo ne montre qu'un seul déposant.

Retenu : (i), car la démo doit être reproductible par un relecteur du grant avec le faucet Circle, sans nous demander d'agir.

## 5. Tests

- `test/YieldVault.t.sol` et `test/MorphoYieldVault.t.sol` : unitaires, forge standard, `MockERC20` 6 décimales et `MockERC4626Target` (rendement simulé, refus de dépôt, liquidité limitée, `max*` à 0 comme un Vault V2).
- Cas obligatoires : constructeur (actif incohérent, adresse nulle, rôles cumulés) ; dépôt placé en entier, allowance nulle ensuite ; refus de Morpho qui fait échouer le dépôt entier ; montée de NAV après rendement ; retrait et rachat ; arrondi après retrait Morpho (le client ne reçoit jamais plus que `previewRedeem`) ; liquidité insuffisante sans effet de bord ; pause, désallocation, évacuation et état terminal ; appels non autorisés par un tiers (sender, receiver et owner toujours distincts dans les helpers).
- `test/MorphoYieldVault.fuzz.t.sol` : invariant de solvabilité `totalAssets() >= convertToAssets(totalSupply())` sur dépôts, rendements et retraits aléatoires.
- `test/fork/MorphoArcMainnet.fork.t.sol` : sous `arc-anvil` uniquement, dépôt puis rachat contre le Vault V2 USDC mainnet retenu, en lecture sur une copie locale. Ignoré en CI si le binaire manque, et dit dans le journal.
- CI GitHub Actions : `forge fmt --check`, `forge build`, `forge test`, `forge coverage` avec un seuil bloquant de 95 % des lignes et des branches sur `src/`, Slither sans finding haut ou moyen.

## 6. Script CCTP

Deux approches : (a) script TypeScript avec `viem` (`scripts/cctp/`), qui enchaîne approbation exacte, `depositForBurn`, attente de l'attestation Circle et `receiveMessage` ; (b) commandes `cast` et `curl` dans un script shell. Choix : (a). Le sondage de l'attestation et le décodage de sa réponse sont du code, pas une commande, et le fichier sert de capture lisible pour la vidéo. `viem` est la seule dépendance ajoutée : rien dans le dépôt ne parle HTTP ni JSON-RPC typé.

Route : Base Sepolia vers Arc testnet, USDC. EURC si S4 le confirme, sinon EURC pris directement au faucet Circle sur Arc testnet et le point est noté.

## 7. Déploiement et preuves

1. `script/Deploy.s.sol` : déploie une instance USDC et une instance EURC du même bytecode, owner, guardian et recovery sur trois clés locales distinctes. Vérification Blockscout testnet.
2. Dépôt et rachat de démo sur chaque instance, depuis un compte déposant distinct de l'owner.
3. `docs/evidence/` : un fichier par livrable, entrées datées le jour de la preuve, même format que les deux autres dépôts (ce que la preuve établit, hash et lien explorer, adresse, commit, empreinte du bytecode on-chain comparée au build de `main`).
4. `docs/evidence/screenshots/` : une capture PNG par produit Circle (USDC, EURC, CCTP), plus Morpho.

## 8. Fichiers

```
LICENSE                       MIT, Copyright (c) 2026 ForYield
README.md                     portée, adresses testnet, interface, build, déploiement, roadmap
.gitignore  .gitmodules  foundry.toml
src/YieldVault.sol
src/MorphoYieldVault.sol
lib/vault-v2                  submodule Morpho épinglé, jamais importé par src/
script/deploy-morpho-target.sh  déploie le Vault V2 cible sur testnet
script/Deploy.s.sol
script/DemoFlow.s.sol         dépôt et rachat de démo
test/YieldVault.t.sol
test/MorphoYieldVault.t.sol
test/MorphoYieldVault.fuzz.t.sol
test/fork/MorphoArcMainnet.fork.t.sol
test/mocks/MockERC20.sol  test/mocks/MockERC4626Target.sol
scripts/cctp/base-sepolia-to-arc.ts  scripts/cctp/package.json
.github/workflows/ci.yml
docs/plans/2026-09-21-arc-morpho-vault-design.md   ce document
docs/plans/2026-09-21-spikes.md                    verdicts S1 à S5
docs/evidence/README.md
docs/evidence/a1-vault-testnet.md
docs/evidence/a2-cctp.md
docs/evidence/screenshots/
```

## 9. Ordre de marche

Chaque étape donne un commit autonome.

1. Ossature : licence, README minimal, Foundry, submodules, CI.
2. Spikes S1 à S5, verdicts écrits.
3. `YieldVault`, test d'abord.
4. `MorphoYieldVault`, test d'abord, puis fuzz et fork.
5. Déploiement testnet, vérification de source, dépôt et rachat, journal A1.
6. Script CCTP, exécution réelle, journal A2.
7. README complet, captures.

## 10. Vérifications finales

`forge build`, `forge test` (fuzz inclus), couverture au seuil, Slither, `forge fmt --check` ; relecture du diff complet ; empreinte du bytecode on-chain égale au build de `main` ; aucune approbation illimitée ; aucune clé ni `.env` versionnés.

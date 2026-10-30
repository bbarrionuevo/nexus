// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.34;

// Cazador de MidnightBundlesV2, fase 2: crear y cancelar ofertas con CancelAndMake sobre Morpho Blue,
// BlueBuyCallbackFactory, PriceRatifierV1 y Log reales, y las ventas de la fase 1 tomando esas ofertas, que pagan
// desde Blue. Además de las leyes BU-... de la fase 1 en cada entrada de toma:
//   MK-CANCEL  cada grupo cancelado queda con consumo máximo;
//   MK-PARK    lo estacionado sale del usuario y entra exacto a la posición en Blue del BlueBuyCallback de ese usuario
//              y esa sal (sin interés ni deuda incobrable en Blue, el precio de las acciones no cambia);
//   MK-RATIFY  con una raíz nueva, el ratifier queda autorizado por el usuario y la raíz ratificada para él;
//   MK-COLL    el colateral aportado entra exacto a la posición del usuario en Midnight;
//   MK-ISO     nada de los demás cambia: autorizaciones, raíces, consumos de sus grupos y posiciones en Blue de los
//              callbacks ajenos;
//   MK-LIVE    revierte si y solo si el plazo venció o algún grupo ya superaba su maxConsumed;
//   BU-CB      en una toma, la posición en Blue de un callback solo baja si su dueño compró unidades en esa llamada,
//              nunca sube, y el callback no se queda con saldo. Algunas ofertas usan el callback de otro usuario: no
//              tienen que poder cobrarle;
//   BU-TAKE    una oferta creada solo la toma su allowedTaker (si tiene) y solo mientras su raíz está ratificada.

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {Offer} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {PriceRatifierV1} from "../../lib/midnight/src/ratifiers/PriceRatifierV1.sol";
import {HashLib} from "../../lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {BlueBuyCallbackFactory} from "../../lib/midnight/src/periphery/blue-buy-callback/BlueBuyCallbackFactory.sol";
import {BlueBuyCallback} from "../../lib/midnight/src/periphery/blue-buy-callback/BlueBuyCallback.sol";
import {Log} from "../../lib/midnight/src/periphery/log/Log.sol";
import {IMorpho, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {GroupCancellation, CollateralTransfer, OfferFill} from "../../src/midnight/interfaces/IMidnightBundlesV2.sol";
import {NexusMidnightBundlesHandler} from "./NexusMidnightBundles.t.sol";

contract NexusMidnightBundlesMakeHandler is NexusMidnightBundlesHandler {
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;

    uint256 internal constant BLUE_LLTV = 0.86e18;
    uint256 internal constant NS = 2; // sales de callback por usuario
    uint256 internal constant MAX_MADE = 64;

    IMorpho internal blue;
    BlueBuyCallbackFactory internal factory;
    PriceRatifierV1 internal pr;
    MarketParams internal bmp;
    address[8] internal cbs; // BlueBuyCallback de (dueño, sal) en dueño * NS + sal, existan o no (CREATE2)
    bool[8] internal cbLive; // los que ya se crearon (con un estacionamiento que pasó)
    uint8 internal constant NO_CB = 255; // oferta sin callback: paga el creador

    /// @dev Una oferta de compra creada con CancelAndMake, para volver a armarla al tomarla.
    struct Made {
        uint8 m; // creador
        uint8 cbOwner; // dueño del callback que paga (distinto del creador: un intento de cobrarle a otro; NO_CB: sin callback)
        uint8 cbSalt;
        bool reduceOnly;
        bool capUnits;
        uint128 cap;
        uint256 tick;
        bytes32 group;
        address allowedTaker;
        bytes32 root;
        uint8 leafIndex;
        bytes32 sibling; // 0 si el árbol tiene una sola hoja
    }

    Made[] internal made;
    bool internal onlyMade; // en sellMade: todas las ofertas de la venta son creadas
    bytes32[] internal roots; // raíces ratificadas, con su creador en rootMaker
    uint8[] internal rootMaker;

    // métricas de la fase 2
    uint256 internal hMakes;
    uint256 internal hMakesOk;
    uint256 internal hCancels;
    uint256 internal hParks;
    uint256 internal hRoots;
    uint256 internal hCbTaken; // tomas en las que un callback pagó desde Blue
    uint256 internal hForeignCb; // ofertas creadas con el callback de otro usuario
    uint256 internal hBlueOps;
    uint256 internal hUnratified;
    uint256 internal hMadeTaken; // ofertas creadas que se tomaron (su grupo consumió)

    constructor(uint256 sfPct, uint256 cfPct) NexusMidnightBundlesHandler(sfPct, cfPct) {
        pr = new PriceRatifierV1(address(midnight));
        for (uint256 i; i < NH * NS; ++i) {
            cbs[i] = _cbAddr(i / NS, i % NS);
        }
        for (uint256 h; h < NH; ++h) {
            vm.startPrank(accts[h]);
            loan.approve(address(blue), type(uint256).max);
            coll[0].approve(address(blue), type(uint256).max);
            vm.stopPrank();
        }
    }

    /// @dev Blue real (0.8.19, por deployCode) sin interés, con un mercado del mismo activo prestado que Midnight; la
    /// fábrica de BlueBuyCallback y el Log reales.
    function _periphery() internal override returns (address, address, address) {
        blue = IMorpho(deployCode("Morpho.sol", abi.encode(address(this))));
        blue.enableIrm(address(0));
        blue.enableLltv(BLUE_LLTV);
        bmp = MarketParams({
            loanToken: address(loan),
            collateralToken: address(coll[0]),
            oracle: address(oracle[0]),
            irm: address(0),
            lltv: BLUE_LLTV
        });
        blue.createMarket(bmp);
        factory = new BlueBuyCallbackFactory(address(midnight), address(blue));
        return (address(blue), address(factory), address(new Log()));
    }

    /* CREAR Y CANCELAR OFERTAS */

    struct MakeIn {
        uint256 u;
        GroupCancellation[] gc;
        bool overMax;
        CollateralTransfer[] cs;
        uint256 park;
        uint256 salt;
        uint256 nOffers;
        bytes32 root;
        uint256 deadline;
    }

    struct MakePre {
        uint256 userLoan;
        uint256 blueLoan;
        uint256 cbSupply;
        uint256 m0;
        uint256 m1;
        bool[4] authPr;
        bool[] rootOk;
        uint128[] madeConsumed;
        uint256[] cbSupplies;
        uint256 bLoan;
        uint256 bC0;
        uint256 bC1;
    }

    function make(uint256 userSeed, uint256 seed, uint256 amtSeed) external {
        MakeIn memory x;
        x.u = userSeed % NH;
        uint256 s = _h(seed, 20);
        address user = accts[x.u];
        // grupos a cancelar: de 0 a 2, de las ofertas del usuario o nuevos
        x.gc = new GroupCancellation[](s % 3);
        for (uint256 k; k < x.gc.length; ++k) {
            uint256 sk = _h(seed, 21 + k);
            bytes32 g = _userGroup(x.u, sk);
            uint128 c = midnight.consumed(user, g);
            for (uint256 j; j < k; ++j) {
                if (x.gc[j].group == g) c = type(uint128).max; // la cancelación anterior ya lo dejó en el máximo
            }
            uint256 mode = (sk >> 64) % 4;
            uint128 mx = mode == 0 ? type(uint128).max : (mode == 1 || c == 0 ? c : c - 1);
            if (c > mx) x.overMax = true;
            x.gc[k] = GroupCancellation({group: g, maxConsumed: mx});
        }
        // colateral: 0 o 1 aporte
        x.cs = new CollateralTransfer[]((s >> 8) % 2);
        if (x.cs.length > 0) {
            x.cs[0] = CollateralTransfer({collateralIndex: (s >> 9) % NC, assets: _amt(amtSeed, 82, AMT)});
            coll[x.cs[0].collateralIndex].mint(user, x.cs[0].assets);
        }
        // ofertas nuevas: 0 (sin raíz), 1 o 2 en un árbol; estacionar en Blue la mitad de las veces, o 7 de cada 8
        // si hay ofertas nuevas (que casi siempre usan el callback recién financiado)
        x.nOffers = (s >> 12) % 3;
        x.salt = (s >> 10) % NS;
        if ((s >> 11) % 8 < (x.nOffers > 0 ? 7 : 4)) {
            x.park = _amt(amtSeed, 84, AMT);
            loan.mint(user, x.park);
        }
        if (x.nOffers > 0) x.root = _newTree(x.u, x.nOffers, _h(seed, 30), x.park > 0 ? x.salt : NS);
        x.deadline = (s >> 20) % 32 == 0 ? block.timestamp - 1 : block.timestamp;

        MakePre memory pre = _makePre(x);
        vm.prank(user);
        (bool ok,) = address(bundle).call(
            abi.encodeCall(
                bundle.midnightBundlesV2CancelAndMake,
                (bmp, x.park, bytes32(x.salt), _market(), x.cs, address(pr), x.root, uint256(0), uint128(0),
                    uint256(0), uint8(0), bytes32(0), bytes32(0), x.gc, abi.encode("nexus", seed), x.deadline,
                    address(0))
            )
        );
        ++hMakes;
        bool mustRevert = x.overMax || x.deadline < block.timestamp;
        _ok(ok == !mustRevert, L_LIVE, "MK-LIVE: CancelAndMake no revirtio si y solo si el plazo vencio o un grupo superaba maxConsumed (paso, debia revertir)", ok ? 1 : 0, mustRevert ? 1 : 0);
        if (!ok) {
            if (x.nOffers > 0) made.pop(); // las ofertas de este árbol no quedaron ratificadas
            if (x.nOffers > 1) made.pop();
            return;
        }
        ++hMakesOk;
        _makeLaws(x, pre);
        if (x.root != bytes32(0)) {
            roots.push(x.root);
            rootMaker.push(uint8(x.u));
            ++hRoots;
        }
        if (x.park > 0) {
            ++hParks;
            cbLive[x.u * NS + x.salt] = true;
        }
        hCancels += x.gc.length;
    }

    /// @dev Un grupo del usuario: el de una de sus ofertas creadas o uno nuevo.
    function _userGroup(uint256 u, uint256 sk) internal view returns (bytes32) {
        if (made.length > 0 && sk % 2 == 0) {
            Made memory d = made[(sk >> 8) % made.length];
            if (d.m == u) return d.group;
        }
        return keccak256(abi.encode("nexus.mb.cancel", u, sk));
    }

    /// @dev Arma 1 o 2 ofertas de compra del usuario, financiadas por un BlueBuyCallback (casi siempre el suyo), las
    /// guarda y devuelve la raíz del árbol.
    function _newTree(uint256 u, uint256 n, uint256 s, uint256 salt) internal returns (bytes32 root) {
        bytes32[2] memory leaves;
        uint256 first = made.length;
        for (uint256 k; k < n; ++k) {
            uint256 sk = uint256(keccak256(abi.encode(s, k)));
            Made memory d;
            d.m = uint8(u);
            (d.cbOwner, d.cbSalt) = _pickCb(u, sk, salt);
            if (d.cbOwner != u && d.cbOwner != NO_CB) ++hForeignCb;
            d.reduceOnly = (sk >> 12) % 8 == 0;
            d.capUnits = (sk >> 16) % 2 == 0;
            d.cap = (sk >> 20) % 3 == 0 ? type(uint128).max : uint128(1 + (sk >> 24) % AMT);
            d.tick = _tick(sk >> 120, true);
            d.group = keccak256(abi.encode("nexus.mb.made", u, ++gNonce));
            d.allowedTaker = (sk >> 28) % 8 == 0 ? accts[(u + 1 + (sk >> 32) % (NH - 1)) % NH] : address(0);
            d.leafIndex = uint8(k);
            leaves[k] = HashLib.hashPriceRatifierV1Offer(_madeOffer(d), d.allowedTaker);
            made.push(d);
        }
        if (n == 1) {
            root = leaves[0];
        } else {
            root = HashLib.hashNode(leaves[0], leaves[1]);
            made[first].sibling = leaves[1];
            made[first + 1].sibling = leaves[0];
        }
        for (uint256 i = first; i < made.length; ++i) {
            made[i].root = root;
        }
        // tope de ofertas guardadas: se descartan las más viejas (y siguen tomables, solo que el fuzzer no las ve)
        if (made.length > MAX_MADE) {
            for (uint256 i; i + n < made.length; ++i) {
                made[i] = made[i + n];
            }
            for (uint256 k; k < n; ++k) {
                made.pop();
            }
            // el árbol nuevo quedó al final; sus hermanos siguen bien porque se movieron juntos
        }
    }

    /// @dev El callback de una oferta nueva: casi siempre uno del creador que exista o que este CancelAndMake cree
    /// (`salt` < NS si estaciona); a veces uno de otro usuario que exista (no tiene que poder cobrarle); 1 de cada 16
    /// cualquiera, exista o no (con uno sin código, la venta que lo toque revierte entera: clase conocida, Spearbit
    /// 5.1.5); si el creador no tiene ninguno, sin callback (paga él).
    function _pickCb(uint256 u, uint256 sk, uint256 salt) internal view returns (uint8, uint8) {
        uint256 r = (sk >> 4) % 16;
        if (r == 0) {
            uint256 i = (sk >> 8) % (NH * NS);
            return (uint8(i / NS), uint8(i % NS));
        }
        if (r <= 2) {
            for (uint256 j; j < NH * NS; ++j) {
                uint256 i = ((sk >> 8) + j) % (NH * NS);
                if (i / NS != u && cbLive[i]) return (uint8(i / NS), uint8(i % NS));
            }
        }
        if (salt < NS && (sk >> 12) % 4 != 0) return (uint8(u), uint8(salt));
        for (uint256 j; j < NS; ++j) {
            uint256 k = ((sk >> 14) + j) % NS;
            if (cbLive[u * NS + k]) return (uint8(u), uint8(k));
        }
        if (salt < NS) return (uint8(u), uint8(salt));
        return (NO_CB, 0);
    }

    function _madeOffer(Made memory d) internal view returns (Offer memory o) {
        o.market = _market();
        o.buy = true;
        o.maker = accts[d.m];
        o.expiry = type(uint256).max;
        o.tick = d.tick;
        o.group = d.group;
        if (d.cbOwner != NO_CB) {
            o.callback = cbs[uint256(d.cbOwner) * NS + d.cbSalt];
            o.callbackData = abi.encode(bmp);
        }
        o.ratifier = address(pr);
        o.reduceOnly = d.reduceOnly;
        if (d.capUnits) o.maxUnits = d.cap;
        else o.maxAssets = d.cap;
        o.continuousFeeCap = type(uint256).max;
    }

    function _ratifierData(Made memory d) internal pure returns (bytes memory) {
        bytes32[] memory proof = new bytes32[](d.sibling == bytes32(0) ? 0 : 1);
        if (proof.length > 0) proof[0] = d.sibling;
        return abi.encode(d.root, uint256(d.leafIndex), proof, d.allowedTaker);
    }

    /// @dev La dirección del BlueBuyCallback de (dueño, sal), exista o no (CREATE2 de la fábrica).
    function _cbAddr(uint256 owner, uint256 salt) internal view returns (address) {
        bytes memory init = abi.encodePacked(
            type(BlueBuyCallback).creationCode, abi.encode(accts[owner], address(midnight), address(blue))
        );
        return vm.computeCreate2Address(bytes32(salt), keccak256(init), address(factory));
    }

    function _cbSupply(address cb) internal view returns (uint256) {
        return blue.expectedSupplyAssets(bmp, cb);
    }

    function _makePre(MakeIn memory x) internal view returns (MakePre memory pre) {
        address user = accts[x.u];
        pre.userLoan = loan.balanceOf(user);
        pre.blueLoan = loan.balanceOf(address(blue));
        pre.cbSupply = _cbSupply(cbs[x.u * NS + x.salt]);
        pre.m0 = midnight.collateral(id, user, 0);
        pre.m1 = midnight.collateral(id, user, 1);
        for (uint256 h; h < NH; ++h) {
            pre.authPr[h] = midnight.isAuthorized(accts[h], address(pr));
        }
        pre.rootOk = new bool[](roots.length);
        for (uint256 i; i < roots.length; ++i) {
            pre.rootOk[i] = pr.isRootRatified(accts[rootMaker[i]], roots[i]);
        }
        pre.madeConsumed = new uint128[](made.length);
        for (uint256 i; i < made.length; ++i) {
            pre.madeConsumed[i] = midnight.consumed(accts[made[i].m], made[i].group);
        }
        pre.cbSupplies = new uint256[](NH * NS);
        for (uint256 i; i < NH * NS; ++i) {
            pre.cbSupplies[i] = _cbSupply(cbs[i]);
        }
        pre.bLoan = loan.balanceOf(address(bundle));
        pre.bC0 = coll[0].balanceOf(address(bundle));
        pre.bC1 = coll[1].balanceOf(address(bundle));
    }

    function _makeLaws(MakeIn memory x, MakePre memory pre) internal {
        address user = accts[x.u];
        for (uint256 k; k < x.gc.length; ++k) {
            uint128 c = midnight.consumed(user, x.gc[k].group);
            _ok(c == type(uint128).max, L_LIMIT, "MK-CANCEL: un grupo cancelado no quedo con consumo maximo (grupo, consumo)", k, c);
        }
        // lo estacionado: del usuario a Blue, a la posición del callback de (usuario, sal)
        int256 paid = int256(pre.userLoan) - int256(loan.balanceOf(user));
        int256 entered = int256(loan.balanceOf(address(blue))) - int256(pre.blueLoan);
        _okI(paid == int256(x.park), L_FUNDS, "MK-PARK: el usuario no pago exactamente lo estacionado (esperado, pagado)", int256(x.park), paid);
        _okI(entered == int256(x.park), L_FUNDS, "MK-PARK: a Blue no entro exactamente lo estacionado (esperado, entrado)", int256(x.park), entered);
        address cb = cbs[x.u * NS + x.salt];
        if (x.park > 0) {
            _ok(factory.callbackOf(user, bytes32(x.salt)) == cb, L_FUNDS, "MK-PARK: el callback del usuario no es el de CREATE2 (sal, 0)", x.salt, 0);
        }
        _ok(_cbSupply(cb) == pre.cbSupply + x.park, L_FUNDS, "MK-PARK: la posicion en Blue del callback no subio exactamente lo estacionado (esperado, real)", pre.cbSupply + x.park, _cbSupply(cb));
        // ratificación
        if (x.root != bytes32(0)) {
            _ok(midnight.isAuthorized(user, address(pr)), L_LIMIT, "MK-RATIFY: el ratifier no quedo autorizado por el usuario (usuario, 0)", x.u, 0);
            _ok(pr.isRootRatified(user, x.root), L_LIMIT, "MK-RATIFY: la raiz nueva no quedo ratificada para el usuario (usuario, 0)", x.u, 0);
        }
        // colateral
        uint256[2] memory in_;
        for (uint256 k; k < x.cs.length; ++k) {
            in_[x.cs[k].collateralIndex] += x.cs[k].assets;
        }
        _ok(midnight.collateral(id, user, 0) == pre.m0 + in_[0] && midnight.collateral(id, user, 1) == pre.m1 + in_[1], L_LIMIT, "MK-COLL: el colateral del usuario no subio exactamente lo aportado (esperado 0, real 0)", pre.m0 + in_[0], midnight.collateral(id, user, 0));
        // nada de los demás cambia
        for (uint256 h; h < NH; ++h) {
            if (h == x.u) continue;
            _ok(midnight.isAuthorized(accts[h], address(pr)) == pre.authPr[h], L_ISO, "MK-ISO: cambio la autorizacion del ratifier de otro usuario (usuario, 0)", h, 0);
        }
        for (uint256 i; i < pre.rootOk.length; ++i) {
            if (rootMaker[i] == x.u) continue;
            _ok(pr.isRootRatified(accts[rootMaker[i]], roots[i]) == pre.rootOk[i], L_ISO, "MK-ISO: cambio una raiz de otro usuario (raiz, usuario)", i, rootMaker[i]);
        }
        for (uint256 i; i < pre.madeConsumed.length; ++i) {
            if (made[i].m == x.u) continue;
            _ok(midnight.consumed(accts[made[i].m], made[i].group) == pre.madeConsumed[i], L_ISO, "MK-ISO: cambio el consumo de un grupo de otro usuario (oferta, usuario)", i, made[i].m);
        }
        for (uint256 i; i < NH * NS; ++i) {
            if (i / NS == x.u && i % NS == x.salt) continue;
            _ok(_cbSupply(cbs[i]) == pre.cbSupplies[i], L_ISO, "MK-ISO: cambio la posicion en Blue de otro callback (dueno, sal)", i / NS, i % NS);
        }
        _ok(loan.balanceOf(address(bundle)) == pre.bLoan && coll[0].balanceOf(address(bundle)) == pre.bC0 && coll[1].balanceOf(address(bundle)) == pre.bC1, L_FUNDS, "MK-PARK: el bundle quedo con saldo despues de CancelAndMake (activo, colateral 0)", loan.balanceOf(address(bundle)), coll[0].balanceOf(address(bundle)));
    }

    /// @dev Un creador des-ratifica una de sus raíces directo en el ratifier: sus ofertas dejan de ser tomables.
    function unratify(uint256 seed) external {
        uint256 hs = _h(seed, 42);
        if (roots.length == 0 || hs % 4 != 0) return;
        uint256 i = (hs >> 2) % roots.length;
        vm.prank(accts[rootMaker[i]]);
        pr.setIsRootRatified(accts[rootMaker[i]], roots[i], false);
        ++hUnratified;
    }

    /* BLUE: LIQUIDEZ Y USO */

    /// @dev Otro actor deposita en Blue (más liquidez para los callbacks).
    function blueSupply(uint256 seed, uint256 amt) external {
        uint256 h = _h(seed, 40) % NH;
        uint256 a = _amt(amt, 86, AMT);
        loan.mint(accts[h], a);
        vm.prank(accts[h]);
        blue.supply(bmp, a, 0, accts[h], "");
        ++hBlueOps;
    }

    /// @dev Otro actor pide prestado en Blue (menos liquidez: un callback puede no poder pagar todo lo que tiene).
    function blueBorrow(uint256 seed, uint256 amt) external {
        uint256 h = _h(seed, 41) % NH;
        (uint256 tsa,, uint256 tba,) = blue.expectedMarketBalances(bmp);
        uint256 liq = tsa - tba;
        if (liq == 0) return;
        uint256 a = _amt(amt, 88, liq / 4 + 1); // a lo sumo un cuarto: que quede liquidez para los callbacks casi siempre
        uint256 p = oracle[0].price();
        if (p == 0) return;
        uint256 c = (a * WAD / BLUE_LLTV + 1) * PSCALE / p + 1;
        c += c / 2;
        coll[0].mint(accts[h], c);
        vm.startPrank(accts[h]);
        blue.supplyCollateral(bmp, c, accts[h], "");
        (bool ok,) = address(blue).call(abi.encodeCall(blue.borrow, (bmp, a, 0, accts[h], accts[h])));
        vm.stopPrank();
        if (ok) ++hBlueOps;
    }

    /* TOMAR LAS OFERTAS CREADAS */

    /// @dev Una venta solo contra ofertas creadas, con un objetivo de 1e15 a 1e21 que entre en lo que tienen: las
    /// ventas exigen llenar el objetivo exacto, y con objetivos grandes revertían enteras. El monto sale de un hash: con
    /// las semillas chicas del fuzzer quedaba en unos pocos wei, que se llenan sin mover activos.
    function sellMade(uint256 userSeed, uint256 offersSeed, uint256 paramsSeed, uint256 collSeed) external {
        if (made.length == 0) return;
        onlyMade = true;
        uint256 small = 1e15 + _h(paramsSeed, 61) % 1e21;
        if (_h(paramsSeed, 60) % 2 == 0) this.sellUnits(userSeed, offersSeed, small, collSeed);
        else this.sellAssets(userSeed, offersSeed, small, collSeed);
        onlyMade = false;
    }

    /// @dev En las ventas, la mitad de las ofertas (salvo una primera mala) pasan a ser ofertas creadas con
    /// CancelAndMake por otros usuarios, con su prueba de Merkle.
    function _fills(P memory p, bool takerBuys, uint256 seed) internal override returns (OfferFill[] memory f) {
        f = super._fills(p, takerBuys, seed);
        if (takerBuys || made.length == 0) return f;
        uint256 h = _h(seed, 50);
        for (uint256 k = p.badFirst ? 1 : 0; k < f.length; ++k) {
            if (!onlyMade && (h >> (2 * k)) % 4 == 0) continue;
            Made memory d = made[(h >> (8 + 24 * k)) % made.length];
            if (d.m == p.u) continue;
            f[k].offer = _madeOffer(d);
            f[k].ratifierData = _ratifierData(d);
            p.maker[d.m] = true;
            if (d.cbOwner == NO_CB) loan.mint(accts[d.m], 2 * AMT); // sin callback paga el creador
        }
    }

    function _extLoan() internal view override returns (uint256 t) {
        t = loan.balanceOf(address(blue));
        for (uint256 i; i < NH * NS; ++i) {
            t += loan.balanceOf(cbs[i]);
        }
    }

    /// @dev Por callback: su posición en Blue y su saldo.
    function _extState() internal view override returns (uint256[] memory st) {
        st = new uint256[](2 * NH * NS + made.length);
        for (uint256 i; i < NH * NS; ++i) {
            st[2 * i] = _cbSupply(cbs[i]);
            st[2 * i + 1] = loan.balanceOf(cbs[i]);
        }
        for (uint256 i; i < made.length; ++i) {
            st[2 * NH * NS + i] = midnight.consumed(accts[made[i].m], made[i].group);
        }
    }

    /// @dev BU-CB después de cada toma que pasó.
    function _extLaws(uint256 kind, P memory p, Snap memory pre, Snap memory post) internal override {
        for (uint256 i; i < NH * NS; ++i) {
            uint256 o = i / NS;
            uint256 a = pre.extState[2 * i];
            uint256 b = post.extState[2 * i];
            _ok(b <= a, L_ISO, "BU-CB: una toma subio la posicion en Blue de un callback (dueno, entrada)", o, kind);
            if (b < a) {
                ++hCbTaken;
                bool bought = o < NH && p.maker[o] && _du(pre, post, o) > 0;
                _ok(bought, L_ISO, "BU-CB: un callback pago desde Blue sin que su dueno comprara unidades (dueno, entrada)", o, kind);
            }
            _ok(post.extState[2 * i + 1] == 0, L_FUNDS, "BU-CB: un callback quedo con saldo despues de una toma (dueno, saldo)", o, post.extState[2 * i + 1]);
        }
        uint256 base = 2 * NH * NS;
        for (uint256 i; i < made.length && base + i < pre.extState.length; ++i) {
            if (post.extState[base + i] == pre.extState[base + i]) continue;
            ++hMadeTaken;
            Made memory d = made[i];
            _ok(d.allowedTaker == address(0) || d.allowedTaker == accts[p.u], L_ISO, "BU-TAKE: tomo una oferta creada alguien que no es su allowedTaker (oferta, quien llama)", i, p.u);
            _ok(pr.isRootRatified(accts[d.m], d.root), L_ISO, "BU-TAKE: se tomo una oferta creada de una raiz no ratificada (oferta, creador)", i, d.m);
        }
    }

    function makeCoverage() external view returns (uint256[10] memory c) {
        c = [hMakes, hMakesOk, hCancels, hParks, hRoots, hCbTaken, hForeignCb, hBlueOps, hUnratified, hMadeTaken];
    }
}

contract NexusMidnightBundlesMakeTest is Test {
    NexusMidnightBundlesMakeHandler internal handler;

    function setUp() public virtual {
        handler = new NexusMidnightBundlesMakeHandler(_sf(), _cf());
        bytes4[] memory sels = new bytes4[](13);
        sels[0] = handler.buyUnits.selector;
        sels[1] = handler.sellUnits.selector;
        sels[2] = handler.buyAssets.selector;
        sels[3] = handler.sellAssets.selector;
        sels[4] = handler.position.selector;
        sels[5] = handler.warp.selector;
        sels[6] = handler.setPrice.selector;
        sels[7] = handler.repayDirect.selector;
        sels[8] = handler.make.selector;
        sels[9] = handler.blueSupply.selector;
        sels[10] = handler.blueBorrow.selector;
        sels[11] = handler.unratify.selector;
        sels[12] = handler.sellMade.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: sels}));
        targetContract(address(handler));
    }

    function _sf() internal pure virtual returns (uint256) {
        return 50;
    }

    function _cf() internal pure virtual returns (uint256) {
        return 0;
    }

    function invariant_midnightBundlesMake() public view {
        string memory err = handler.check();
        require(bytes(err).length == 0, err);
    }

    function afterInvariant() public {
        (uint256 laws, uint256[4] memory calls, uint256[4] memory oks,,,,) = handler.coverage();
        uint256[10] memory c = handler.makeCoverage();
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("cobertura: llamadas de toma al bundle", calls[0] + calls[1] + calls[2] + calls[3]);
        emit log_named_uint("cobertura: tomas que pasaron", oks[0] + oks[1] + oks[2] + oks[3]);
        emit log_named_uint("cobertura: CancelAndMake", c[0]);
        emit log_named_uint("cobertura: CancelAndMake que pasaron", c[1]);
        emit log_named_uint("cobertura: grupos cancelados", c[2]);
        emit log_named_uint("cobertura: estacionamientos en Blue", c[3]);
        emit log_named_uint("cobertura: raices ratificadas", c[4]);
        emit log_named_uint("cobertura: tomas pagadas por un callback desde Blue", c[5]);
        emit log_named_uint("cobertura: ofertas con el callback de otro usuario", c[6]);
        emit log_named_uint("cobertura: operaciones directas en Blue", c[7]);
        emit log_named_uint("cobertura: raices des-ratificadas", c[8]);
        emit log_named_uint("cobertura: ofertas creadas tomadas", c[9]);
        (uint256[10] memory r,,,,) = handler.revertCounts();
        emit log_named_uint("reversiones: OutOfOffers", r[0]);
        emit log_named_uint("reversiones: SellerAssetsTooLow", r[3]);
        emit log_named_uint("reversiones: NotReduceOnly", r[4]);
        emit log_named_uint("reversiones: validaciones", r[5]);
        emit log_named_uint("reversiones: panico aritmetico", r[6]);
        emit log_named_uint("reversiones: otras", r[7]);
        emit log_named_uint("reversiones: sin datos (callback sin codigo)", r[9]);
    }
}

/// @dev Comisiones al máximo: la de liquidación en cada punto y la continua.
contract NexusMidnightBundlesMakeFeesTest is NexusMidnightBundlesMakeTest {
    function _sf() internal pure override returns (uint256) {
        return 100;
    }

    function _cf() internal pure override returns (uint256) {
        return 100;
    }
}

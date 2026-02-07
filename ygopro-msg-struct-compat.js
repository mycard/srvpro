"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.fromPartialCompat = exports.applyYGOProMsgStructCompat = exports.defineYGOProMsgStructCompat = exports.YGOProMsgStructCompat = void 0;
const ygopro_deck_encode_1 = __importDefault(require("ygopro-deck-encode"));
const ygopro_msg_encode_1 = require("ygopro-msg-encode");
exports.YGOProMsgStructCompat = new Map();
const defineYGOProMsgStructCompat = (cls, field, getterAndSetter) => {
    if (!exports.YGOProMsgStructCompat.has(cls)) {
        exports.YGOProMsgStructCompat.set(cls, []);
    }
    exports.YGOProMsgStructCompat.get(cls).push((inst) => {
        Object.defineProperty(inst, field, {
            get() {
                return getterAndSetter.get(inst);
            },
            set(value) {
                getterAndSetter.set(inst, value);
            }
        });
    });
};
exports.defineYGOProMsgStructCompat = defineYGOProMsgStructCompat;
const applyYGOProMsgStructCompat = (inst) => {
    const compatList = exports.YGOProMsgStructCompat.get(inst.constructor);
    if (compatList) {
        compatList.forEach(compat => compat(inst));
    }
    return inst;
};
exports.applyYGOProMsgStructCompat = applyYGOProMsgStructCompat;
const fromPartialCompat = (cls, input) => {
    const inst1 = new cls();
    (0, exports.applyYGOProMsgStructCompat)(inst1);
    Object.assign(inst1, input);
    const inst2 = new cls().fromPartial(inst1);
    (0, exports.applyYGOProMsgStructCompat)(inst2);
    return inst2;
};
exports.fromPartialCompat = fromPartialCompat;
const compatDeckState = new WeakMap();
const getCompatDeckState = (inst) => {
    let state = compatDeckState.get(inst);
    if (!state) {
        state = {};
        compatDeckState.set(inst, state);
    }
    return state;
};
(0, exports.defineYGOProMsgStructCompat)(ygopro_msg_encode_1.YGOProStocChat, "player", {
    get(inst) {
        return inst.player_type;
    },
    set(inst, value) {
        inst.player_type = value;
    },
});
(0, exports.defineYGOProMsgStructCompat)(ygopro_msg_encode_1.YGOProStocDeckCount, "mainc_s", {
    get(inst) {
        return inst.player0DeckCount?.main ?? 0;
    },
    set(inst, value) {
        if (!inst.player0DeckCount) {
            inst.player0DeckCount = new ygopro_msg_encode_1.YGOProStocDeckCount_DeckInfo();
        }
        inst.player0DeckCount.main = value;
    },
});
(0, exports.defineYGOProMsgStructCompat)(ygopro_msg_encode_1.YGOProStocDeckCount, "sidec_s", {
    get(inst) {
        return inst.player0DeckCount?.side ?? 0;
    },
    set(inst, value) {
        if (!inst.player0DeckCount) {
            inst.player0DeckCount = new ygopro_msg_encode_1.YGOProStocDeckCount_DeckInfo();
        }
        inst.player0DeckCount.side = value;
    },
});
(0, exports.defineYGOProMsgStructCompat)(ygopro_msg_encode_1.YGOProStocDeckCount, "extrac_s", {
    get(inst) {
        return inst.player0DeckCount?.extra ?? 0;
    },
    set(inst, value) {
        if (!inst.player0DeckCount) {
            inst.player0DeckCount = new ygopro_msg_encode_1.YGOProStocDeckCount_DeckInfo();
        }
        inst.player0DeckCount.extra = value;
    },
});
(0, exports.defineYGOProMsgStructCompat)(ygopro_msg_encode_1.YGOProStocDeckCount, "mainc_o", {
    get(inst) {
        return inst.player1DeckCount?.main ?? 0;
    },
    set(inst, value) {
        if (!inst.player1DeckCount) {
            inst.player1DeckCount = new ygopro_msg_encode_1.YGOProStocDeckCount_DeckInfo();
        }
        inst.player1DeckCount.main = value;
    },
});
(0, exports.defineYGOProMsgStructCompat)(ygopro_msg_encode_1.YGOProStocDeckCount, "sidec_o", {
    get(inst) {
        return inst.player1DeckCount?.side ?? 0;
    },
    set(inst, value) {
        if (!inst.player1DeckCount) {
            inst.player1DeckCount = new ygopro_msg_encode_1.YGOProStocDeckCount_DeckInfo();
        }
        inst.player1DeckCount.side = value;
    },
});
(0, exports.defineYGOProMsgStructCompat)(ygopro_msg_encode_1.YGOProStocDeckCount, "extrac_o", {
    get(inst) {
        return inst.player1DeckCount?.extra ?? 0;
    },
    set(inst, value) {
        if (!inst.player1DeckCount) {
            inst.player1DeckCount = new ygopro_msg_encode_1.YGOProStocDeckCount_DeckInfo();
        }
        inst.player1DeckCount.extra = value;
    },
});
(0, exports.defineYGOProMsgStructCompat)(ygopro_msg_encode_1.YGOProCtosUpdateDeck, "mainc", {
    get(inst) {
        return inst.deck.main.length + inst.deck.extra.length;
    },
    set(inst, value) {
        const state = getCompatDeckState(inst);
        state.mainc = value;
    },
});
(0, exports.defineYGOProMsgStructCompat)(ygopro_msg_encode_1.YGOProCtosUpdateDeck, "sidec", {
    get(inst) {
        return inst.deck.side.length;
    },
    set(inst, value) {
        const state = getCompatDeckState(inst);
        state.sidec = value;
    },
});
(0, exports.defineYGOProMsgStructCompat)(ygopro_msg_encode_1.YGOProCtosUpdateDeck, "deckbuf", {
    get(inst) {
        return [...inst.deck.main, ...inst.deck.extra, ...inst.deck.side];
    },
    set(inst, value) {
        const state = getCompatDeckState(inst);
        const deckbuf = Array.isArray(value) ? value.slice() : [];
        state.deckbuf = deckbuf;
        if (!inst.deck) {
            inst.deck = new ygopro_deck_encode_1.default();
        }
        const hasMainc = state.mainc !== undefined;
        const hasSidec = state.sidec !== undefined;
        if (!hasMainc && !hasSidec) {
            inst.deck.main = deckbuf.slice();
            inst.deck.extra = [];
            inst.deck.side = [];
            return;
        }
        if (hasMainc && !hasSidec) {
            const mainc = Math.max(0, state.mainc | 0);
            const mainWithExtra = deckbuf.slice(0, mainc);
            const side = deckbuf.slice(mainc);
            inst.deck.main = mainWithExtra.slice();
            inst.deck.extra = [];
            inst.deck.side = side.slice();
            return;
        }
        if (!hasMainc && hasSidec) {
            const sidec = Math.max(0, state.sidec | 0);
            const split = Math.max(0, deckbuf.length - sidec);
            const mainWithExtra = deckbuf.slice(0, split);
            const side = deckbuf.slice(split);
            inst.deck.main = mainWithExtra.slice();
            inst.deck.extra = [];
            inst.deck.side = side.slice();
            return;
        }
        const mainc = Math.max(0, state.mainc | 0);
        const sidec = Math.max(0, state.sidec | 0);
        const mainWithExtra = deckbuf.slice(0, mainc);
        const side = deckbuf.slice(mainc, mainc + sidec);
        inst.deck.main = mainWithExtra.slice();
        inst.deck.extra = [];
        inst.deck.side = side.slice();
    },
});

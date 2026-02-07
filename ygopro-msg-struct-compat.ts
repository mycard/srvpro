import YGOProDeck from "ygopro-deck-encode";
import {
  YGOProCtosUpdateDeck,
  YGOProCtosBase, YGOProStocBase,
  YGOProStocChat,
  YGOProStocDeckCount,
  YGOProStocDeckCount_DeckInfo,
} from "ygopro-msg-encode";

export const YGOProMsgStructCompat = new Map<new (...args: any[]) => YGOProCtosBase | YGOProStocBase, ((inst: YGOProCtosBase | YGOProStocBase) => void)[]>();
export const defineYGOProMsgStructCompat = <T extends YGOProCtosBase | YGOProStocBase>(cls: new (...args: any[]) => T, field: string, getterAndSetter: {
  get: (inst: T) => any,
  set: (inst: T, value: any) => void
}) => {
  if (!YGOProMsgStructCompat.has(cls)) { 
    YGOProMsgStructCompat.set(cls, []);
  }
  YGOProMsgStructCompat.get(cls)!.push((inst: YGOProCtosBase | YGOProStocBase) => { 
    Object.defineProperty(inst, field, {
      get() { 
        return getterAndSetter.get(inst as T);
      },
      set(value) { 
        getterAndSetter.set(inst as T, value);
      }
    })
  })
}

export const applyYGOProMsgStructCompat = (inst: YGOProCtosBase | YGOProStocBase) => { 
  const compatList = YGOProMsgStructCompat.get(inst.constructor as typeof YGOProCtosBase | typeof YGOProStocBase);
  if (compatList) { 
    compatList.forEach(compat => compat(inst));
  }
  return inst;
}

export const fromPartialCompat = <T extends YGOProCtosBase | YGOProStocBase>(
  cls: new (...args: any[]) => T,
  input: Partial<T>
): T => {
  const inst1 = new cls();
  applyYGOProMsgStructCompat(inst1);
  Object.assign(inst1, input);
  const inst2 = new cls().fromPartial(inst1 as Partial<T>) as T;
  applyYGOProMsgStructCompat(inst2);
  return inst2;
};

const compatDeckState = new WeakMap<
  YGOProCtosUpdateDeck,
  { mainc?: number; sidec?: number; deckbuf?: number[] }
>();

const getCompatDeckState = (inst: YGOProCtosUpdateDeck) => {
  let state = compatDeckState.get(inst);
  if (!state) {
    state = {};
    compatDeckState.set(inst, state);
  }
  return state;
};

defineYGOProMsgStructCompat(YGOProStocChat, "player", {
  get(inst) {
    return inst.player_type;
  },
  set(inst, value) {
    inst.player_type = value;
  },
});

defineYGOProMsgStructCompat(YGOProStocDeckCount, "mainc_s", {
  get(inst) {
    return inst.player0DeckCount?.main ?? 0;
  },
  set(inst, value) {
    if (!inst.player0DeckCount) {
      inst.player0DeckCount = new YGOProStocDeckCount_DeckInfo();
    }
    inst.player0DeckCount.main = value;
  },
});

defineYGOProMsgStructCompat(YGOProStocDeckCount, "sidec_s", {
  get(inst) {
    return inst.player0DeckCount?.side ?? 0;
  },
  set(inst, value) {
    if (!inst.player0DeckCount) {
      inst.player0DeckCount = new YGOProStocDeckCount_DeckInfo();
    }
    inst.player0DeckCount.side = value;
  },
});

defineYGOProMsgStructCompat(YGOProStocDeckCount, "extrac_s", {
  get(inst) {
    return inst.player0DeckCount?.extra ?? 0;
  },
  set(inst, value) {
    if (!inst.player0DeckCount) {
      inst.player0DeckCount = new YGOProStocDeckCount_DeckInfo();
    }
    inst.player0DeckCount.extra = value;
  },
});

defineYGOProMsgStructCompat(YGOProStocDeckCount, "mainc_o", {
  get(inst) {
    return inst.player1DeckCount?.main ?? 0;
  },
  set(inst, value) {
    if (!inst.player1DeckCount) {
      inst.player1DeckCount = new YGOProStocDeckCount_DeckInfo();
    }
    inst.player1DeckCount.main = value;
  },
});

defineYGOProMsgStructCompat(YGOProStocDeckCount, "sidec_o", {
  get(inst) {
    return inst.player1DeckCount?.side ?? 0;
  },
  set(inst, value) {
    if (!inst.player1DeckCount) {
      inst.player1DeckCount = new YGOProStocDeckCount_DeckInfo();
    }
    inst.player1DeckCount.side = value;
  },
});

defineYGOProMsgStructCompat(YGOProStocDeckCount, "extrac_o", {
  get(inst) {
    return inst.player1DeckCount?.extra ?? 0;
  },
  set(inst, value) {
    if (!inst.player1DeckCount) {
      inst.player1DeckCount = new YGOProStocDeckCount_DeckInfo();
    }
    inst.player1DeckCount.extra = value;
  },
});

defineYGOProMsgStructCompat(YGOProCtosUpdateDeck, "mainc", {
  get(inst) {
    return inst.deck.main.length + inst.deck.extra.length;
  },
  set(inst, value) {
    const state = getCompatDeckState(inst);
    state.mainc = value;
  },
});

defineYGOProMsgStructCompat(YGOProCtosUpdateDeck, "sidec", {
  get(inst) {
    return inst.deck.side.length;
  },
  set(inst, value) {
    const state = getCompatDeckState(inst);
    state.sidec = value;
  },
});

defineYGOProMsgStructCompat(YGOProCtosUpdateDeck, "deckbuf", {
  get(inst) {
    return [...inst.deck.main, ...inst.deck.extra, ...inst.deck.side];
  },
  set(inst, value) {
    const state = getCompatDeckState(inst);
    const deckbuf = Array.isArray(value) ? value.slice() : [];
    state.deckbuf = deckbuf;
    if (!inst.deck) {
      inst.deck = new YGOProDeck();
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

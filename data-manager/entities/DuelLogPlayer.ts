import {Column, Entity, Index, ManyToOne} from "typeorm";
import {BasePlayer} from "./BasePlayer";
import {DuelLog} from "./DuelLog";
import {Deck, decodeDeck, encodeDeck} from "../DeckEncoder";
import {DuelLogPlayerInfo} from "../DataManager";

@Entity()
export class DuelLogPlayer extends BasePlayer {
    @Index()
    @Column({ type: "varchar", length: 20 })
    realName: string;

    @Column({ type: "varchar", length: 64, nullable: true })
    ip: string;

    @Column("tinyint", {unsigned: true})
    isFirst: number;

    @Column("tinyint")
    score: number;

    @Column("int", {nullable: true})
    lp: number;

    @Column("smallint", {nullable: true})
    cardCount: number;

    @Column("text", {nullable: true})
    startDeckBuffer: string;

    @Column("text", {nullable: true})
    currentDeckBuffer: string;

    @Column("tinyint")
    winner: number;

    setStartDeck(deck: Deck) {
        if(deck === null) {
            this.startDeckBuffer = null;
            return;
        }
        this.startDeckBuffer = encodeDeck(deck).toString("base64");
    }

    getStartDeck() {
        return decodeDeck(Buffer.from(this.startDeckBuffer, "base64"));
    }

    setCurrentDeck(deck: Deck) {
        if(deck === null) {
            this.currentDeckBuffer = null;
            return;
        }
        this.currentDeckBuffer = encodeDeck(deck).toString("base64");
    }

    getCurrentDeck() {
        return decodeDeck(Buffer.from(this.currentDeckBuffer, "base64"));
    }

    @ManyToOne(() => DuelLog, duelLog => duelLog.players)
    duelLog: DuelLog;

    static fromDuelLogPlayerInfo(info: DuelLogPlayerInfo) {
        const p = new DuelLogPlayer();
        p.name = info.name;
        p.pos = info.pos;
        p.realName = info.realName;
        p.lp = info.lp;
        p.ip = info.ip;
        p.score = info.score;
        p.cardCount = info.cardCount;
        p.isFirst = info.isFirst ? 1 : 0;
        p.winner = info.winner ? 1 : 0;
        p.startDeckBuffer = info.startDeckBuffer.toString("base64");
        p.setCurrentDeck(info.deck);
        return p;
    }
}

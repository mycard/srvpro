import axios from "axios";
import qs from "querystring";
import moment, {Moment} from "moment";

interface Deck {
	main: number[];
	side: number[];
}

interface Config {
	rankURL: string;
	identifierURL: string;
	athleticFetchParams: any;
	rankCount: number;
	ttl: number;
}

interface AthleticDecksReturnData {
	name: string
}

interface ReturnMessage {
	success: boolean;
	athletic?: boolean;
	message: string;
}

export class AthleticChecker {
	config: Config;
	athleticDeckCache: string[];
	lastAthleticDeckFetchTime: Moment;
	constructor(config: Config) {
		this.config = config;
	}
	deckToString(deck: Deck) {
		const deckText = '#ygopro-server deck log\n#main\n' + deck.main.join('\n') + '\n!side\n' + deck.side.join('\n') + '\n';
		return deckText;
	}
	async getAthleticDecks(): Promise<string[]> {
		if (this.athleticDeckCache && moment().diff(this.lastAthleticDeckFetchTime, "seconds") < this.config.ttl) {
			return this.athleticDeckCache;
		}
		const { data } = await axios.get(this.config.rankURL, {
			timeout: 10000,
			responseType: "json",
			paramsSerializer: qs.stringify,
			params: this.config.athleticFetchParams
		});
		const athleticDecks = (data as AthleticDecksReturnData[]).slice(0, this.config.rankCount).map(m => m.name);
		this.athleticDeckCache = athleticDecks;
		this.lastAthleticDeckFetchTime = moment();
		return athleticDecks;
	}
	async getDeckType(deck: Deck): Promise<string> {
		const deckString = this.deckToString(deck);
		const { data } = await axios.post(this.config.identifierURL, qs.stringify({ deck: deckString }), {
			timeout: 10000,
			responseType: "json"
		});
		return data.deck;
	}
	async checkAthletic(deck: Deck): Promise<ReturnMessage> {
		try {
			const athleticDecks = await this.getAthleticDecks();
			const deckType = await this.getDeckType(deck);
			const athletic = athleticDecks.includes(deckType);
			return { success: true, athletic, message: null }
		} catch (e) {
			return { success: false, message: e.toString() };
		}
	}
}

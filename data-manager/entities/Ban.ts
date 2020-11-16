import {Column, Entity, Index, PrimaryGeneratedColumn, Unique} from "typeorm";
import {CreateAndUpdateTimeBase} from "./CreateAndUpdateTimeBase";

@Entity()
@Unique(["ip", "name"])
export class Ban extends CreateAndUpdateTimeBase {
	@PrimaryGeneratedColumn({ unsigned: true, type: "bigint" })
	id: number;

	@Index()
	@Column({ type: "varchar", length: 64, nullable: true })
	ip: string;

	@Index()
	@Column({ type: "varchar", length: 20, nullable: true })
	name: string;
}

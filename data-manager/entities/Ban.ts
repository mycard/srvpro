import {Column, Entity, Index, PrimaryGeneratedColumn} from "typeorm";

@Entity()
export class Ban {
	@PrimaryGeneratedColumn({ unsigned: true, type: "bigint" })
	id: number;

	@Index()
	@Column({ type: "varchar", length: 64, nullable: true })
	ip: string;

	@Index()
	@Column({ type: "varchar", length: 20, nullable: true })
	name: string;
}

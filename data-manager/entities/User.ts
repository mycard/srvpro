import {Column, Entity, PrimaryColumn} from "typeorm";

@Entity()
export class User {
    @PrimaryColumn({type: "varchar", length: 128})
    key: string;

    @Column("varchar", {length: 16, nullable: true})
    chatColor: string;
}

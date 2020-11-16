import {Column, Entity, PrimaryColumn} from "typeorm";
import {CreateAndUpdateTimeBase} from "./CreateAndUpdateTimeBase";

@Entity()
export class User extends CreateAndUpdateTimeBase {
    @PrimaryColumn({type: "varchar", length: 128})
    key: string;

    @Column("varchar", {length: 16, nullable: true})
    chatColor: string;
}

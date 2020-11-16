import {Column, PrimaryGeneratedColumn} from "typeorm";
import {CreateAndUpdateTimeBase} from "./CreateAndUpdateTimeBase";

export abstract class BasePlayer extends CreateAndUpdateTimeBase {
    @PrimaryGeneratedColumn({unsigned: true, type: "bigint"})
    id: number;

    @Column({ type: "varchar", length: 20 })
    name: string;

    @Column({ type: "tinyint" })
    pos: number;
}
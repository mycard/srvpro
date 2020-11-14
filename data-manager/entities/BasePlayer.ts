import {Column, PrimaryGeneratedColumn} from "typeorm";

export abstract class BasePlayer {
    @PrimaryGeneratedColumn({unsigned: true, type: "bigint"})
    id: number;

    @Column({ type: "varchar", length: 20 })
    name: string;

    @Column({ type: "tinyint" })
    pos: number;
}
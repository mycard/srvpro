import {CreateDateColumn, UpdateDateColumn} from "typeorm";

export abstract class CreateAndUpdateTimeBase {
    @CreateDateColumn()
    createTime: Date;

    @UpdateDateColumn()
    updateTime: Date;
}

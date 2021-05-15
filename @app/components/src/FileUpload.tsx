import React, { useState } from "react";
import InboxOutlined from "@ant-design/icons/InboxOutlined";
import PictureOutlined from "@ant-design/icons/PictureOutlined";
import { Upload } from "antd";
import { UploadFile } from "antd/lib/upload/interface";
import ImgCrop from "antd-img-crop";
import useTranslation from "next-translate/useTranslation";

import "antd/lib/modal/style";
import "antd/lib/slider/style";

const { Dragger } = Upload;

interface FileUploadProps {
  accept: string;
  cropAspect: number;
  "data-cy": string;
  id?: string;
  maxCount?: number;
  onChange?: () => any;
}

export function FileUpload(props: FileUploadProps) {
  const { accept, cropAspect, id, onChange: parentOnChange, maxCount } = props;
  const { t } = useTranslation();

  const [fileList, setFileList] = useState<UploadFile[] | undefined>(undefined);

  const dummyRequest = ({ onSuccess }: any) => {
    setTimeout(() => {
      onSuccess("ok");
    }, 0);
  };

  return (
    <ImgCrop aspect={cropAspect} modalTitle={t("common:imgCropTitle")}>
      <Dragger
        accept={accept}
        beforeUpload={async (file) => {
          // This call to setFileList is needed for some reason. Probably
          // because it triggers a rerender or something...
          setFileList([file as any]);
          return file;
        }}
        customRequest={dummyRequest}
        data-cy={props["data-cy"]}
        fileList={fileList}
        id={id}
        listType="picture-card"
        maxCount={maxCount}
        name="headerImageFile"
        onChange={({ fileList }) => {
          setFileList(fileList);
          // The parentOnChange comes from Form.Item somehow. A property called
          // getValueFromEvent on the Form.Item gets as input what is passed to
          // parentOnChange
          // @ts-ignore
          parentOnChange(fileList);
        }}
      >
        <p className="ant-upload-drag-icon">
          {accept.startsWith("image") ? <PictureOutlined /> : <InboxOutlined />}
        </p>
        <p className="ant-upload-text">{t("common:dragToUpload")}</p>
      </Dragger>
    </ImgCrop>
  );
}

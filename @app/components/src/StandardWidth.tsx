import React from "react";
import { Col, Row } from "antd";

import { contentMaxWidth } from "./SharedLayout";

export interface StandardWidthProps {
  children: React.ReactNode;
}

export const StandardWidth: React.FC<StandardWidthProps> = ({ children }) => (
  <Row style={{ padding: "1rem", maxWidth: contentMaxWidth, margin: "0 auto" }}>
    <Col flex={1}>{children}</Col>
  </Row>
);
